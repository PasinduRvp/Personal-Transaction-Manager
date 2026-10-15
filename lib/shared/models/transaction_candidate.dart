import 'package:equatable/equatable.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/enums.dart';
import '../../core/utils/money.dart';
import 'category.dart';
import 'json_map.dart';
import 'transaction.dart';

/// Names of the candidate fields that carry a confidence score. Used as keys in
/// [TransactionCandidate.fieldConfidence] and by the review UI to decide which
/// inputs to flag.
class CandidateField {
  const CandidateField._();

  static const String merchant = 'merchant';
  static const String amount = 'amount';
  static const String date = 'date';
  static const String currency = 'currency';
  static const String paymentMethod = 'payment_method';
  static const String reference = 'reference';
  static const String category = 'category';
  static const String type = 'type';

  static const List<String> all = [
    merchant,
    amount,
    date,
    currency,
    paymentMethod,
    reference,
    category,
    type,
  ];
}

/// A proposed transaction extracted from a document, before the user confirms
/// it. Persisted as a row of `public.ocr_transactions`.
///
/// This is the boundary the product principle rests on: OCR output becomes a
/// candidate, never a transaction. Only [TransactionCandidate.toTransaction]
/// — called after an explicit user confirmation — produces a real record.
class TransactionCandidate extends Equatable {
  const TransactionCandidate({
    required this.id,
    required this.jobId,
    required this.documentId,
    required this.userId,
    required this.type,
    this.amount,
    this.merchant,
    this.description,
    this.transactionDate,
    this.currency = 'LKR',
    this.suggestedCategoryId,
    this.paymentMethod,
    this.referenceNumber,
    this.accountId,
    this.overallConfidence,
    this.fieldConfidence = const {},
    this.status = OcrCandidateStatus.pending,
    this.duplicateOfTransactionId,
    this.pageNumber,
    this.rawLine,
    this.sortOrder = 0,
    this.createdTransactionId,
    this.suggestedCategory,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String jobId;
  final String documentId;
  final String userId;

  final TransactionType type;

  /// Null when the parser could not find an amount. The review screen then
  /// requires the user to type one; confirmation is blocked until they do.
  final Money? amount;
  final String? merchant;
  final String? description;
  final DateTime? transactionDate;
  final String currency;
  final String? suggestedCategoryId;
  final PaymentMethod? paymentMethod;
  final String? referenceNumber;

  /// The parser never guesses an account — a statement does not say which of
  /// the user's accounts it belongs to unless the user tells us.
  final String? accountId;

  /// 0–1 average across the fields the parser filled.
  final double? overallConfidence;

  /// Per-field 0–1 scores, keyed by [CandidateField].
  final Map<String, double> fieldConfidence;

  final OcrCandidateStatus status;

  /// Set when duplicate detection matched an existing transaction.
  final String? duplicateOfTransactionId;

  final int? pageNumber;

  /// The exact source line, shown under the fields so the user can check the
  /// extraction against the document.
  final String? rawLine;

  final int sortOrder;

  /// Set once the user confirms and a transaction is created.
  final String? createdTransactionId;

  final Category? suggestedCategory;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isConfirmed => status == OcrCandidateStatus.confirmed;
  bool get isIgnored => status == OcrCandidateStatus.ignored;
  bool get isPossibleDuplicate => duplicateOfTransactionId != null;

  double? confidenceFor(String field) => fieldConfidence[field];

  /// True when a field is missing or scored below the review threshold, so the
  /// UI must ask the user to verify it. A field with no score at all counts as
  /// needing verification — silence is not confidence.
  bool needsVerification(String field) {
    final score = fieldConfidence[field];
    if (score == null) return true;
    return score < AppConstants.lowConfidenceThreshold;
  }

  bool get hasHighConfidenceAmount =>
      amount != null && !needsVerification(CandidateField.amount);

  /// Everything that stops this candidate being confirmed as-is. Rendered as
  /// warnings at the top of the review screen.
  List<CandidateWarning> get warnings {
    final result = <CandidateWarning>[];

    if (amount == null || amount!.isZero) {
      result.add(const CandidateWarning(
        CandidateField.amount,
        'Amount not detected',
        'Enter the transaction amount.',
        blocking: true,
      ));
    } else if (needsVerification(CandidateField.amount)) {
      result.add(const CandidateWarning(
        CandidateField.amount,
        'Amount unclear',
        'Please check the amount against the document.',
      ));
    }

    if (accountId == null) {
      result.add(const CandidateWarning(
        CandidateField.merchant,
        'Account not detected',
        'Please select which account this belongs to.',
        blocking: true,
      ));
    }

    if (transactionDate == null) {
      result.add(const CandidateWarning(
        CandidateField.date,
        'Date not detected',
        'Enter the transaction date.',
        blocking: true,
      ));
    } else if (needsVerification(CandidateField.date)) {
      result.add(const CandidateWarning(
        CandidateField.date,
        'Date unclear',
        'Please verify the date.',
      ));
    }

    if (merchant == null || merchant!.trim().isEmpty) {
      result.add(const CandidateWarning(
        CandidateField.merchant,
        'Merchant not detected',
        'Add a merchant or description so you can recognise this later.',
      ));
    } else if (needsVerification(CandidateField.merchant)) {
      result.add(const CandidateWarning(
        CandidateField.merchant,
        'Merchant unclear',
        'Please check the merchant name.',
      ));
    }

    if (suggestedCategoryId == null && type != TransactionType.transfer) {
      result.add(const CandidateWarning(
        CandidateField.category,
        'Category not suggested',
        'Choose a category to keep your reports accurate.',
      ));
    }

    if (isPossibleDuplicate) {
      result.add(const CandidateWarning(
        CandidateField.reference,
        'Possible duplicate',
        'A similar transaction already exists.',
      ));
    }

    return result;
  }

  /// Blocking warnings must be resolved before the Confirm button enables.
  bool get canConfirm => !warnings.any((w) => w.blocking);

  factory TransactionCandidate.fromJson(Json json) {
    final currency = json.str('currency', fallback: 'LKR');
    final categoryJson = json.relation('suggested_category');
    final rawConfidence = json.jsonVal('field_confidence');
    return TransactionCandidate(
      id: json.str('id'),
      jobId: json.str('job_id'),
      documentId: json.str('document_id'),
      userId: json.str('user_id'),
      type: TransactionType.fromWire(json.strOrNull('transaction_type')),
      amount: json.moneyOrNull('amount', fallbackCurrency: currency),
      merchant: json.strOrNull('merchant'),
      description: json.strOrNull('description'),
      transactionDate: json.dateOrNull('transaction_date'),
      currency: currency,
      suggestedCategoryId: json.strOrNull('suggested_category_id'),
      paymentMethod: PaymentMethod.fromWire(json.strOrNull('payment_method')),
      referenceNumber: json.strOrNull('reference_number'),
      accountId: json.strOrNull('account_id'),
      overallConfidence: json.dblOrNull('confidence'),
      fieldConfidence: {
        for (final entry in rawConfidence.entries)
          if (entry.value is num) entry.key: (entry.value as num).toDouble(),
      },
      status: OcrCandidateStatus.fromWire(json.strOrNull('status')),
      duplicateOfTransactionId: json.strOrNull('duplicate_of_transaction_id'),
      pageNumber: json.intOrNull('page_number'),
      rawLine: json.strOrNull('raw_line'),
      sortOrder: json.intVal('sort_order'),
      createdTransactionId: json.strOrNull('created_transaction_id'),
      suggestedCategory:
          categoryJson == null ? null : Category.fromJson(categoryJson),
      createdAt: json.dateVal('created_at'),
      updatedAt: json.dateVal('updated_at'),
    );
  }

  /// Persists the user's edits back onto the candidate row.
  ///
  /// Only the candidate is rewritten — `ocr_results.raw_text` is immutable, so
  /// correcting a misread never destroys the original OCR output.
  Json toUpdateJson() => compactJson({
        'transaction_type': type.wire,
        ...moneyFields('amount', amount, withCurrency: false),
        'currency': currency,
        'merchant': merchant ?? Patch.clear,
        'description': description ?? Patch.clear,
        'transaction_date': transactionDate == null
            ? Patch.clear
            : dateOnly(transactionDate!),
        'suggested_category_id': suggestedCategoryId ?? Patch.clear,
        'payment_method': paymentMethod?.wire ?? Patch.clear,
        'reference_number': referenceNumber ?? Patch.clear,
        'account_id': accountId ?? Patch.clear,
        'status': status.wire,
      });

  /// Builds the transaction to insert once the user has confirmed.
  ///
  /// The result is deliberately [TransactionStatus.confirmed]: the pending
  /// state exists while the candidate awaits review, and confirmation is the
  /// act that promotes it. Callers must have checked [canConfirm] first.
  Transaction toTransaction({
    required String accountId,
    required TransactionSource source,
    String? categoryId,
    TransactionStatus status = TransactionStatus.confirmed,
  }) {
    final resolvedAmount = amount;
    if (resolvedAmount == null || resolvedAmount.isZero) {
      throw StateError(
        'Cannot build a transaction from a candidate with no amount.',
      );
    }
    return Transaction(
      id: '',
      userId: userId,
      accountId: accountId,
      categoryId: categoryId ?? suggestedCategoryId,
      type: type,
      amount: resolvedAmount.abs,
      description: description,
      merchant: merchant,
      paymentMethod: paymentMethod,
      transactionDate: transactionDate ?? DateTime.now(),
      documentId: documentId,
      source: source,
      status: status,
      referenceNumber: referenceNumber,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  TransactionCandidate copyWith({
    TransactionType? type,
    Object? amount = _sentinel,
    Object? merchant = _sentinel,
    Object? description = _sentinel,
    Object? transactionDate = _sentinel,
    String? currency,
    Object? suggestedCategoryId = _sentinel,
    Object? paymentMethod = _sentinel,
    Object? referenceNumber = _sentinel,
    Object? accountId = _sentinel,
    Map<String, double>? fieldConfidence,
    OcrCandidateStatus? status,
    Object? duplicateOfTransactionId = _sentinel,
    Object? createdTransactionId = _sentinel,
    Category? suggestedCategory,
  }) =>
      TransactionCandidate(
        id: id,
        jobId: jobId,
        documentId: documentId,
        userId: userId,
        type: type ?? this.type,
        amount: amount == _sentinel ? this.amount : amount as Money?,
        merchant: merchant == _sentinel ? this.merchant : merchant as String?,
        description: description == _sentinel
            ? this.description
            : description as String?,
        transactionDate: transactionDate == _sentinel
            ? this.transactionDate
            : transactionDate as DateTime?,
        currency: currency ?? this.currency,
        suggestedCategoryId: suggestedCategoryId == _sentinel
            ? this.suggestedCategoryId
            : suggestedCategoryId as String?,
        paymentMethod: paymentMethod == _sentinel
            ? this.paymentMethod
            : paymentMethod as PaymentMethod?,
        referenceNumber: referenceNumber == _sentinel
            ? this.referenceNumber
            : referenceNumber as String?,
        accountId:
            accountId == _sentinel ? this.accountId : accountId as String?,
        overallConfidence: overallConfidence,
        fieldConfidence: fieldConfidence ?? this.fieldConfidence,
        status: status ?? this.status,
        duplicateOfTransactionId: duplicateOfTransactionId == _sentinel
            ? this.duplicateOfTransactionId
            : duplicateOfTransactionId as String?,
        pageNumber: pageNumber,
        rawLine: rawLine,
        sortOrder: sortOrder,
        createdTransactionId: createdTransactionId == _sentinel
            ? this.createdTransactionId
            : createdTransactionId as String?,
        suggestedCategory: suggestedCategory ?? this.suggestedCategory,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  static const Object _sentinel = Object();

  @override
  List<Object?> get props => [
        id,
        jobId,
        documentId,
        type,
        amount,
        merchant,
        description,
        transactionDate,
        currency,
        suggestedCategoryId,
        paymentMethod,
        referenceNumber,
        accountId,
        overallConfidence,
        fieldConfidence,
        status,
        duplicateOfTransactionId,
        pageNumber,
        createdTransactionId,
      ];
}

/// A single message shown above the review form.
class CandidateWarning extends Equatable {
  const CandidateWarning(
    this.field,
    this.title,
    this.detail, {
    this.blocking = false,
  });

  final String field;
  final String title;
  final String detail;

  /// Blocking warnings prevent confirmation entirely.
  final bool blocking;

  @override
  List<Object?> get props => [field, title, detail, blocking];
}

/// An existing transaction that looks like a candidate, with the reasons why.
class DuplicateMatch extends Equatable {
  const DuplicateMatch({
    required this.existing,
    required this.score,
    required this.reasons,
  });

  final Transaction existing;

  /// 0–1. Higher means more likely the same transaction.
  final double score;
  final List<String> reasons;

  bool get isStrong => score >= 0.85;

  @override
  List<Object?> get props => [existing, score, reasons];
}
