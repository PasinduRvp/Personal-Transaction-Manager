import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../core/constants/enums.dart';
import '../../core/utils/money.dart';
import 'account.dart';
import 'category.dart';
import 'json_map.dart';

/// A row of `public.transactions`, optionally joined to its account, category
/// and splits.
///
/// [amount] is always a positive magnitude; the direction of money movement is
/// derived from [type] and [transferDirection] via [signedAmount]. Keeping the
/// stored amount unsigned lets a single `amount > 0` check constraint guard
/// every row, and means a mis-set sign can never silently invert a balance.
class Transaction extends Equatable {
  const Transaction({
    required this.id,
    required this.userId,
    required this.accountId,
    required this.type,
    required this.amount,
    required this.transactionDate,
    this.categoryId,
    this.description,
    this.merchant,
    this.paymentMethod,
    this.notes,
    this.documentId,
    this.source = TransactionSource.manual,
    this.status = TransactionStatus.confirmed,
    this.transferGroupId,
    this.transferDirection,
    this.transferPeerAccountId,
    this.referenceNumber,
    this.recurringTransactionId,
    this.billId,
    this.savingsGoalId,
    this.lendingId,
    this.isSplit = false,
    this.splits = const [],
    this.account,
    this.category,
    this.transferPeerAccount,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String accountId;
  final String? categoryId;
  final TransactionType type;

  /// Always positive. See the class comment.
  final Money amount;
  final String? description;
  final String? merchant;
  final PaymentMethod? paymentMethod;
  final DateTime transactionDate;
  final String? notes;

  /// The attached receipt or statement, if any (`documents.id`).
  final String? documentId;
  final TransactionSource source;
  final TransactionStatus status;

  /// Shared by the two rows of one transfer.
  final String? transferGroupId;
  final TransferDirection? transferDirection;
  final String? transferPeerAccountId;

  /// Bank reference / receipt number, used for duplicate detection.
  final String? referenceNumber;
  final String? recurringTransactionId;
  final String? billId;
  final String? savingsGoalId;

  /// Set when this is the principal or a repayment leg of a lending
  /// record. Written only by `LendingRepository`; a transaction carrying
  /// one must not be edited or deleted from the generic transaction screens
  /// — the parent `lendings/{id}` document would drift out of step.
  final String? lendingId;
  final bool isSplit;

  /// Populated when the row was fetched with its splits.
  final List<TransactionSplit> splits;

  /// Populated when the row was fetched with `select('*, account:accounts(*)')`.
  final Account? account;
  final Category? category;
  final Account? transferPeerAccount;

  final DateTime createdAt;
  final DateTime updatedAt;

  String get currency => amount.currency;

  /// Negative for money leaving an account, positive for money arriving.
  /// This is the only place the sign convention is defined.
  Money get signedAmount {
    switch (type) {
      case TransactionType.income:
        return amount;
      case TransactionType.expense:
        return -amount;
      case TransactionType.transfer:
        return transferDirection == TransferDirection.incoming
            ? amount
            : -amount;
    }
  }

  bool get isPending => status == TransactionStatus.pending;
  bool get isFromOcr => source.isOcr;
  bool get hasAttachment => documentId != null;

  /// Transfers are internal movements and must be excluded from income and
  /// expense totals.
  bool get countsAsIncome =>
      type == TransactionType.income && status == TransactionStatus.confirmed;
  bool get countsAsExpense =>
      type == TransactionType.expense && status == TransactionStatus.confirmed;

  /// Primary line of a transaction row: the merchant if known, else the
  /// description, else the category, else a generic label.
  String get title {
    final m = merchant?.trim();
    if (m != null && m.isNotEmpty) return m;
    final d = description?.trim();
    if (d != null && d.isNotEmpty) return d;
    final c = category?.name;
    if (c != null && c.isNotEmpty) return c;
    if (type.isTransfer) {
      return transferDirection == TransferDirection.incoming
          ? 'Transfer in'
          : 'Transfer out';
    }
    return type.label;
  }

  /// Secondary line: description when the title already used the merchant.
  String? get subtitle {
    final m = merchant?.trim();
    final d = description?.trim();
    if (m != null && m.isNotEmpty && d != null && d.isNotEmpty && d != m) {
      return d;
    }
    if (type.isTransfer) {
      final peer = transferPeerAccount?.name;
      if (peer != null) {
        return transferDirection == TransferDirection.incoming
            ? 'From $peer'
            : 'To $peer';
      }
    }
    return category?.name;
  }

  IconData get icon {
    if (lendingId != null) {
      return transferDirection == TransferDirection.incoming
          ? Icons.call_received_rounded
          : Icons.call_made_rounded;
    }
    if (type.isTransfer) return Icons.swap_horiz_rounded;
    return category?.icon ??
        (type == TransactionType.income
            ? Icons.arrow_downward_rounded
            : Icons.receipt_long_outlined);
  }

  /// The sum of the split lines, or zero when the transaction is not split.
  Money get splitTotal => splits.isEmpty
      ? Money.zero(currency)
      : splits.map((s) => s.amount).reduce((a, b) => a + b);

  /// True when the split lines do not reconcile with the parent amount. The
  /// database enforces this too; this getter drives the warning banner.
  bool get hasSplitMismatch => isSplit && splits.isNotEmpty && splitTotal != amount;

  factory Transaction.fromJson(Json json) {
    final currency = json.str('currency', fallback: 'LKR');
    final accountJson = json.relation('account');
    final categoryJson = json.relation('category');
    final peerJson = json.relation('transfer_peer_account');
    return Transaction(
      id: json.str('id'),
      userId: json.str('user_id'),
      accountId: json.str('account_id'),
      categoryId: json.strOrNull('category_id'),
      type: TransactionType.fromWire(json.strOrNull('type')),
      amount: json.money('amount', currencyKey: 'currency', fallbackCurrency: currency),
      description: json.strOrNull('description'),
      merchant: json.strOrNull('merchant'),
      paymentMethod: PaymentMethod.fromWire(json.strOrNull('payment_method')),
      transactionDate: json.dateVal('transaction_date'),
      notes: json.strOrNull('notes'),
      documentId: json.strOrNull('document_id'),
      source: TransactionSource.fromWire(json.strOrNull('source')),
      status: TransactionStatus.fromWire(json.strOrNull('status')),
      transferGroupId: json.strOrNull('transfer_group_id'),
      transferDirection:
          TransferDirection.fromWire(json.strOrNull('transfer_direction')),
      transferPeerAccountId: json.strOrNull('transfer_peer_account_id'),
      referenceNumber: json.strOrNull('reference_number'),
      recurringTransactionId: json.strOrNull('recurring_transaction_id'),
      billId: json.strOrNull('bill_id'),
      savingsGoalId: json.strOrNull('savings_goal_id'),
      lendingId: json.strOrNull('lending_id'),
      isSplit: json.boolVal('is_split'),
      splits: json
          .relationList('splits')
          .map(TransactionSplit.fromJson)
          .toList(growable: false),
      account: accountJson == null ? null : Account.fromJson(accountJson),
      category: categoryJson == null ? null : Category.fromJson(categoryJson),
      transferPeerAccount: peerJson == null ? null : Account.fromJson(peerJson),
      createdAt: json.dateVal('created_at'),
      updatedAt: json.dateVal('updated_at'),
    );
  }

  /// Insert payload. `user_id` is never sent — the column defaults to
  /// `auth.uid()` and RLS rejects anything else.
  Json toInsertJson() => compactJson({
        'account_id': accountId,
        'category_id': categoryId,
        'type': type.wire,
        ...moneyFields('amount', amount),
        'description': description,
        'merchant': merchant,
        'payment_method': paymentMethod?.wire,
        'transaction_date': Timestamp.fromDate(transactionDate),
        'notes': notes,
        'document_id': documentId,
        'source': source.wire,
        'status': status.wire,
        'transfer_group_id': transferGroupId,
        'transfer_direction': transferDirection?.wire,
        'transfer_peer_account_id': transferPeerAccountId,
        'reference_number': referenceNumber,
        'recurring_transaction_id': recurringTransactionId,
        'bill_id': billId,
        'savings_goal_id': savingsGoalId,
        'lending_id': lendingId,
        'is_split': isSplit,
        'search_terms': searchTerms(
          [merchant, description, notes, referenceNumber],
          prefixed: [merchant],
        ),
      });

  Json toUpdateJson() => compactJson({
        'account_id': accountId,
        'category_id': categoryId ?? Patch.clear,
        'type': type.wire,
        ...moneyFields('amount', amount),
        'description': description ?? Patch.clear,
        'merchant': merchant ?? Patch.clear,
        'payment_method': paymentMethod?.wire ?? Patch.clear,
        'transaction_date': Timestamp.fromDate(transactionDate),
        'notes': notes ?? Patch.clear,
        'document_id': documentId ?? Patch.clear,
        'status': status.wire,
        'reference_number': referenceNumber ?? Patch.clear,
        'is_split': isSplit,
        'search_terms': searchTerms(
          [merchant, description, notes, referenceNumber],
          prefixed: [merchant],
        ),
      });

  Transaction copyWith({
    String? accountId,
    Object? categoryId = _sentinel,
    TransactionType? type,
    Money? amount,
    Object? description = _sentinel,
    Object? merchant = _sentinel,
    Object? paymentMethod = _sentinel,
    DateTime? transactionDate,
    Object? notes = _sentinel,
    Object? documentId = _sentinel,
    TransactionSource? source,
    TransactionStatus? status,
    Object? referenceNumber = _sentinel,
    bool? isSplit,
    List<TransactionSplit>? splits,
    Account? account,
    Category? category,
  }) =>
      Transaction(
        id: id,
        userId: userId,
        accountId: accountId ?? this.accountId,
        categoryId:
            categoryId == _sentinel ? this.categoryId : categoryId as String?,
        type: type ?? this.type,
        amount: amount ?? this.amount,
        description: description == _sentinel
            ? this.description
            : description as String?,
        merchant: merchant == _sentinel ? this.merchant : merchant as String?,
        paymentMethod: paymentMethod == _sentinel
            ? this.paymentMethod
            : paymentMethod as PaymentMethod?,
        transactionDate: transactionDate ?? this.transactionDate,
        notes: notes == _sentinel ? this.notes : notes as String?,
        documentId:
            documentId == _sentinel ? this.documentId : documentId as String?,
        source: source ?? this.source,
        status: status ?? this.status,
        transferGroupId: transferGroupId,
        transferDirection: transferDirection,
        transferPeerAccountId: transferPeerAccountId,
        referenceNumber: referenceNumber == _sentinel
            ? this.referenceNumber
            : referenceNumber as String?,
        recurringTransactionId: recurringTransactionId,
        billId: billId,
        savingsGoalId: savingsGoalId,
        lendingId: lendingId,
        isSplit: isSplit ?? this.isSplit,
        splits: splits ?? this.splits,
        account: account ?? this.account,
        category: category ?? this.category,
        transferPeerAccount: transferPeerAccount,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  static const Object _sentinel = Object();

  @override
  List<Object?> get props => [
        id,
        accountId,
        categoryId,
        type,
        amount,
        description,
        merchant,
        paymentMethod,
        transactionDate,
        notes,
        documentId,
        source,
        status,
        transferGroupId,
        transferDirection,
        referenceNumber,
        isSplit,
        splits,
        updatedAt,
      ];
}

/// A row of `public.transaction_splits`: one line of a split transaction.
class TransactionSplit extends Equatable {
  const TransactionSplit({
    required this.id,
    required this.transactionId,
    required this.amount,
    this.categoryId,
    this.description,
    this.category,
    this.sortOrder = 0,
  });

  final String id;
  final String transactionId;
  final Money amount;
  final String? categoryId;
  final String? description;
  final Category? category;
  final int sortOrder;

  String get label =>
      description?.trim().isNotEmpty == true
          ? description!.trim()
          : (category?.name ?? 'Split');

  factory TransactionSplit.fromJson(Json json) {
    final categoryJson = json.relation('category');
    return TransactionSplit(
      id: json.str('id'),
      transactionId: json.str('transaction_id'),
      amount: json.money('amount'),
      categoryId: json.strOrNull('category_id'),
      description: json.strOrNull('description'),
      category: categoryJson == null ? null : Category.fromJson(categoryJson),
      sortOrder: json.intVal('sort_order'),
    );
  }

  Json toInsertJson(String transactionId) => compactJson({
        'transaction_id': transactionId,
        ...moneyFields('amount', amount),
        'category_id': categoryId,
        'description': description,
        'sort_order': sortOrder,
      });

  TransactionSplit copyWith({
    Money? amount,
    Object? categoryId = _sentinel,
    Object? description = _sentinel,
    Category? category,
    int? sortOrder,
  }) =>
      TransactionSplit(
        id: id,
        transactionId: transactionId,
        amount: amount ?? this.amount,
        categoryId:
            categoryId == _sentinel ? this.categoryId : categoryId as String?,
        description: description == _sentinel
            ? this.description
            : description as String?,
        category: category ?? this.category,
        sortOrder: sortOrder ?? this.sortOrder,
      );

  static const Object _sentinel = Object();

  @override
  List<Object?> get props =>
      [id, transactionId, amount, categoryId, description, sortOrder];
}

/// One day's worth of transactions, used to render the grouped history list.
class TransactionDayGroup extends Equatable {
  const TransactionDayGroup({
    required this.date,
    required this.transactions,
  });

  final DateTime date;
  final List<Transaction> transactions;

  /// Net movement for the day, ignoring transfers so the figure reads as
  /// "what this day cost me".
  Money net(String currency) {
    final relevant = transactions.where((t) => t.type.affectsCashflow);
    if (relevant.isEmpty) return Money.zero(currency);
    return relevant.map((t) => t.signedAmount).reduce((a, b) => a + b);
  }

  @override
  List<Object?> get props => [date, transactions];
}
