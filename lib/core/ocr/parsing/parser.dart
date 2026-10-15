/// Turns recognised text into transaction candidates.
///
/// Deliberately separate from the recogniser: the recogniser's only job is text,
/// and this module's only job is interpretation. That split is what makes the
/// parser unit-testable against fixed strings, with no camera and no model — and it
/// is why moving OCR from a cloud API to an on-device one changed nothing here.
///
/// **Nothing in this file writes anything.** It returns candidates, and a candidate
/// is a proposal. Turning one into a transaction requires the user to press Confirm
/// on the review screen, which is the product's central rule.
library;

import 'amounts.dart';
import 'candidate.dart';
import 'classify.dart';
import 'dates.dart';
import 'statement.dart';

export 'amounts.dart';
export 'candidate.dart';
export 'classify.dart';
export 'dates.dart';
export 'statement.dart';

ParseResult parseDocument(String rawText, ParseOptions options) {
  final classification = classifyDocument(rawText);
  final lines = toLines(rawText);

  if (lines.isEmpty) {
    return ParseResult(
      documentKind: classification.kind,
      classificationConfidence: classification.confidence,
      candidates: const [],
      signals: classification.signals,
    );
  }

  // A statement is a table of transactions; everything else describes one.
  if (classification.kind == 'BANK_STATEMENT') {
    final candidates = parseStatementRows(lines, options);
    if (candidates.isNotEmpty) {
      return ParseResult(
        documentKind: classification.kind,
        classificationConfidence: classification.confidence,
        candidates: candidates,
        signals: classification.signals,
      );
    }
    // Classified as a statement but no rows could be read: fall through to the
    // single-transaction parser rather than returning nothing at all.
  }

  final candidate = parseSingleTransaction(lines, rawText, options);

  return ParseResult(
    documentKind: classification.kind,
    classificationConfidence: classification.confidence,
    candidates: candidate == null ? const [] : [candidate],
    signals: classification.signals,
  );
}

/// Receipts, invoices and payment confirmations: one transaction.
ParsedCandidate? parseSingleTransaction(
  List<String> lines,
  String rawText,
  ParseOptions options,
) {
  final currency = detectCurrency(rawText, options.defaultCurrency);
  final amountSelection = selectAmount(lines);
  final date = selectDate(
    lines,
    DateParseOptions(preferDayFirst: options.preferDayFirst),
  );
  final merchant = extractMerchant(lines);
  final payment = extractPaymentMethod(rawText);
  final reference = extractReference(rawText);
  final category =
      suggestCategoryName('${merchant.merchant ?? ''}\n$rawText');

  // A candidate needs at least one fact in it. An amount or a date is a fact; a
  // guess at the merchant taken from the first line is not, and a candidate with
  // nothing but "Thank You" in it is a row the user has to read and then delete.
  // The import reports "no transactions found" instead, which is both true and
  // actionable.
  if (amountSelection.amount == null && date == null) return null;

  final fieldConfidence = <String, double>{};

  if (amountSelection.amount != null) {
    fieldConfidence['amount'] = amountSelection.confidence;
  }
  if (date != null) fieldConfidence['date'] = date.confidence;
  if (merchant.merchant != null) {
    fieldConfidence['merchant'] = merchant.confidence;
  }
  if (payment.method != null) {
    fieldConfidence['payment_method'] = payment.confidence;
  }
  if (reference.reference != null) {
    fieldConfidence['reference'] = reference.confidence;
  }
  if (category.name != null) fieldConfidence['category'] = category.confidence;

  // A defaulted currency is a weak claim, so it is scored as one rather than
  // presented to the user as if the document had stated it.
  fieldConfidence['currency'] = _hasCurrencyToken(rawText) ? 0.9 : 0.5;

  final direction = _inferDirection(rawText);
  fieldConfidence['type'] = direction.confidence;

  return ParsedCandidate(
    transactionType: direction.type,
    amount: amountSelection.amount?.value,
    currency: currency,
    merchant: merchant.merchant,
    description: _buildDescription(lines, merchant.merchant),
    transactionDate: date?.iso,
    suggestedCategoryName: category.name,
    paymentMethod: payment.method,
    referenceNumber: reference.reference,
    confidence: meanOf(fieldConfidence.values),
    fieldConfidence: fieldConfidence,
    pageNumber: options.pageNumbers.isEmpty ? 1 : options.pageNumbers.first,
    rawLine: amountSelection.amount?.line ?? (lines.isEmpty ? null : lines.first),
    sortOrder: 0,
  );
}

bool _hasCurrencyToken(String text) => RegExp(
      r'\b(lkr|usd|eur|gbp|inr|aud|sgd|aed|jpy|rs\.?)\b|[$€£₹¥]',
      caseSensitive: false,
    ).hasMatch(text);

/// Decides expense vs income vs transfer.
///
/// Defaults to expense, because a photographed document is overwhelmingly a
/// purchase. Income is only claimed when the text says so explicitly.
({String type, double confidence}) _inferDirection(String text) {
  if (RegExp(
    r'\b(salary|payroll|credited\s*to\s*your|deposit\s*(?:received|confirmation)'
    r'|refund(?:ed)?|you\s*received|received\s*from)\b',
    caseSensitive: false,
  ).hasMatch(text)) {
    return (type: 'INCOME', confidence: 0.75);
  }

  if (RegExp(
    r'\b(fund\s*transfer|transferred\s*to|own\s*account\s*transfer)\b',
    caseSensitive: false,
  ).hasMatch(text)) {
    return (type: 'TRANSFER', confidence: 0.6);
  }

  return (type: 'EXPENSE', confidence: 0.85);
}

/// Builds a short description from the document's item lines, skipping the header
/// and the totals block, so the user sees something recognisable in their history
/// when the merchant name alone is not enough.
String? _buildDescription(List<String> lines, String? merchant) {
  final end = lines.length < 25 ? lines.length : 25;
  if (lines.length <= 1) return null;

  final body = lines
      .sublist(1, end)
      .map((l) => l.trim())
      .where((l) =>
          l.length >= 4 &&
          l.length <= 48 &&
          !RegExp(r'^[\d\s,./\-:()]+$').hasMatch(l) &&
          !RegExp(
            r'\b(total|sub\s*total|vat|gst|nbt|cash|change|balance|tel|invoice|'
            r'receipt|date|time|cashier|thank)\b',
            caseSensitive: false,
          ).hasMatch(l) &&
          (merchant == null ||
              normaliseMerchant(l).toLowerCase() != merchant.toLowerCase()))
      .toList(growable: false);

  if (body.isEmpty) return null;

  final description = body.take(2).join(', ');
  return description.length > 120
      ? '${description.substring(0, 117)}...'
      : description;
}
