/// Bank statement row parsing.
///
/// A statement is a table, and the columns matter: the same number is an expense in
/// the Debit column and income in the Credit column. So the parser works out which
/// trailing number is which before deciding a direction, and when it cannot, it
/// scores the type low so the review screen asks.
///
/// Running-balance columns are the main trap — they look exactly like amounts. They
/// are identified by being the last number on the row and by changing monotonically
/// with the movement, and then excluded.
library;

import 'amounts.dart';
import 'candidate.dart';
import 'classify.dart';
import 'dates.dart';

RegExp _i(String source) => RegExp(source, caseSensitive: false);

/// Rows that are structure, not transactions.
final List<RegExp> _nonTransactionRow = [
  _i(r'\b(opening|closing|available|ledger)\s*balance\b'),
  _i(r'\bbalance\s*(?:b/f|c/f|forward|brought|carried)\b'),
  _i(r'\b(total|sub\s*total|grand\s*total)\b'),
  _i(r'\bstatement\s*(?:period|date|of)\b'),
  _i(r'\bpage\s*\d+\s*(?:of\s*\d+)?\b'),
  _i(r'^\s*(date|description|particulars|narration)\b.*\b(debit|credit|amount|balance)\b'),
  _i(r'\bcontinued\b'),
  _i(r'\bbrought\s*forward\b'),
];

/// Words that mark money leaving the account.
final RegExp _debitHints = _i(
    r'\b(dr|debit|withdrawal|withdrawn|payment|purchase|charge|fee|atm|pos|paid|'
    r'transfer\s*out|standing\s*order)\b');

/// Words that mark money arriving.
final RegExp _creditHints = _i(
    r'\b(cr|credit|deposit|salary|refund|interest|received|transfer\s*in|'
    r'reversal)\b');

class _RowNumber {
  const _RowNumber(this.value, this.raw);
  final double value;
  final String raw;
}

class _StatementRow {
  const _StatementRow({
    required this.line,
    required this.lineIndex,
    required this.dateIso,
    required this.dateConfidence,
    required this.dateAmbiguous,
    required this.description,
    required this.numbers,
  });

  final String line;
  final int lineIndex;
  final String dateIso;
  final double dateConfidence;
  final bool dateAmbiguous;
  final String description;

  /// Every money-shaped number on the row, in order.
  final List<_RowNumber> numbers;
}

List<ParsedCandidate> parseStatementRows(
  List<String> lines,
  ParseOptions options,
) {
  final currency = detectCurrency(lines.join('\n'), options.defaultCurrency);
  final rows = _extractRows(lines, options);

  if (rows.isEmpty) return const [];

  final hasBalanceColumn = _detectBalanceColumn(rows);

  final candidates = <ParsedCandidate>[];
  var sortOrder = 0;

  for (final row in rows) {
    // Drop the running balance before choosing an amount.
    final monetary = hasBalanceColumn && row.numbers.length >= 2
        ? row.numbers.sublist(0, row.numbers.length - 1)
        : row.numbers;

    if (monetary.isEmpty) continue;

    // With debit and credit as separate columns, a row carries one populated
    // value; the layout puts debit first.
    final chosen = monetary.length == 1
        ? monetary.first
        : monetary.reduce((a, b) => b.value.abs() > a.value.abs() ? b : a);

    final amount = chosen.value.abs();
    if (amount == 0) continue;

    final direction = _inferRowDirection(row, monetary, chosen);

    final fieldConfidence = <String, double>{
      'amount': hasBalanceColumn || monetary.length == 1 ? 0.88 : 0.72,
      'date': row.dateConfidence,
      'type': direction.confidence,
      'currency': 0.85,
    };

    final merchant = _extractRowMerchant(row.description);
    if (merchant != null) fieldConfidence['merchant'] = 0.7;

    final category = suggestCategoryName(row.description);
    if (category.name != null) {
      fieldConfidence['category'] = category.confidence * 0.9;
    }

    final reference = _extractRowReference(row.description);
    if (reference != null) fieldConfidence['reference'] = 0.65;

    candidates.add(ParsedCandidate(
      transactionType: direction.type,
      amount: amount,
      currency: currency,
      merchant: merchant,
      description: row.description.isEmpty ? null : row.description,
      transactionDate: row.dateIso,
      suggestedCategoryName: category.name,
      paymentMethod: _inferRowPaymentMethod(row.description),
      referenceNumber: reference,
      confidence: meanOf(fieldConfidence.values),
      fieldConfidence: fieldConfidence,
      pageNumber: options.pageNumbers.isEmpty ? null : options.pageNumbers.first,
      rawLine: row.line,
      sortOrder: sortOrder++,
    ));
  }

  return candidates;
}

final RegExp _rowDatePattern = RegExp(
  r'^\s*(\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}|\d{4}[/\-.]\d{1,2}[/\-.]\d{1,2}|'
  r'\d{1,2}\s+[A-Za-z]{3,9}\.?,?\s*\d{0,4})',
);

final RegExp _rowNumberPattern = RegExp(
  r'(-)?\s*(\d{1,3}(?:[,\s]\d{3})+(?:\.\d{1,2})?|\d+\.\d{2})\s*(cr|dr)?',
  caseSensitive: false,
);

final RegExp _firstNumberPattern =
    RegExp(r'(-)?\s*(\d{1,3}(?:[,\s]\d{3})+(?:\.\d{1,2})?|\d+\.\d{2})');

/// Pulls out the rows that begin with a date and contain at least one number.
List<_StatementRow> _extractRows(List<String> lines, ParseOptions options) {
  final rows = <_StatementRow>[];

  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    final line = lines[lineIndex];
    if (_nonTransactionRow.any((p) => p.hasMatch(line))) continue;

    final dateMatch = _rowDatePattern.firstMatch(line);
    if (dateMatch == null) continue;

    final parsed = parseDateToken(
      dateMatch.group(1)!.trim(),
      DateParseOptions(preferDayFirst: options.preferDayFirst),
    );
    if (parsed == null) continue;

    final rest = line.substring(dateMatch.group(0)!.length);

    final numbers = <_RowNumber>[];
    for (final match in _rowNumberPattern.allMatches(rest)) {
      final value = parseAmountToken(match.group(0)!);
      if (value == null || value == 0) continue;
      numbers.add(_RowNumber(value, match.group(0)!.trim()));
    }

    if (numbers.isEmpty) continue;

    // Description is everything before the first number.
    final firstNumber = _firstNumberPattern.firstMatch(rest);
    final description = (firstNumber == null
            ? rest
            : rest.substring(0, firstNumber.start))
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[\s\-|:]+|[\s\-|:]+$'), '')
        .trim();

    rows.add(_StatementRow(
      line: line,
      lineIndex: lineIndex,
      dateIso: parsed.iso,
      // An ambiguous day/month in a statement is slightly safer than on a receipt,
      // because neighbouring rows are usually in order — but it is still ambiguous,
      // so the score stays below the review threshold.
      dateConfidence: parsed.ambiguous ? 0.68 : parsed.confidence,
      dateAmbiguous: parsed.ambiguous,
      description: description,
      numbers: numbers,
    ));
  }

  return rows;
}

/// Detects a running-balance column.
///
/// The test: the last number on each row, taken across rows, moves by roughly the
/// other numbers on those rows. Balances also tend to be the largest value on the
/// row and to repeat closely between consecutive rows, neither of which is true of
/// transaction amounts.
bool _detectBalanceColumn(List<_StatementRow> rows) {
  final multiNumberRows =
      rows.where((r) => r.numbers.length >= 2).toList(growable: false);
  if (multiNumberRows.length < 2) return false;

  var consistent = 0;
  var compared = 0;

  for (var i = 1; i < multiNumberRows.length; i++) {
    final previous = multiNumberRows[i - 1];
    final current = multiNumberRows[i];

    final previousLast = previous.numbers.last.value;
    final currentLast = current.numbers.last.value;

    var movement = 0.0;
    for (final n in current.numbers.sublist(0, current.numbers.length - 1)) {
      final absolute = n.value.abs();
      if (absolute > movement) movement = absolute;
    }

    if (movement == 0) continue;
    compared++;

    final delta = ((currentLast - previousLast).abs() - movement).abs();
    // Within a cent, allowing for a fee or rounding on the row.
    if (delta <= 0.02) consistent++;
  }

  if (compared == 0) {
    // Fall back on the shape: a trailing number that is consistently the largest
    // on its row is a balance.
    final largestIsLast = multiNumberRows.where((r) {
      final last = r.numbers.last.value.abs();
      return r.numbers
          .sublist(0, r.numbers.length - 1)
          .every((n) => n.value.abs() <= last);
    }).length;
    return largestIsLast / multiNumberRows.length >= 0.8;
  }

  return consistent / compared >= 0.6;
}

/// Works out whether a row is money in or money out.
///
/// Column position is the strongest signal when both debit and credit columns are
/// present; otherwise the row's wording decides. When neither is conclusive the
/// confidence is deliberately low — the review screen then shows the type as
/// needing verification rather than filing income as an expense.
({String type, double confidence}) _inferRowDirection(
  _StatementRow row,
  List<_RowNumber> monetary,
  _RowNumber chosen,
) {
  // Explicit Dr/Cr suffix on the number itself.
  if (_i(r'\bcr\b').hasMatch(chosen.raw)) {
    return (type: 'INCOME', confidence: 0.92);
  }
  if (_i(r'\bdr\b').hasMatch(chosen.raw)) {
    return (type: 'EXPENSE', confidence: 0.92);
  }

  // Bracketed or signed negatives are outflows.
  if (chosen.value < 0) return (type: 'EXPENSE', confidence: 0.85);

  final creditWords = _creditHints.hasMatch(row.description);
  final debitWords = _debitHints.hasMatch(row.description);

  if (creditWords && !debitWords) return (type: 'INCOME', confidence: 0.8);
  if (debitWords && !creditWords) return (type: 'EXPENSE', confidence: 0.8);

  // Two populated money columns: debit is conventionally the first.
  if (monetary.length >= 2) {
    final isSecondColumn = monetary.indexOf(chosen) == monetary.length - 1;
    return isSecondColumn
        ? (type: 'INCOME', confidence: 0.6)
        : (type: 'EXPENSE', confidence: 0.6);
  }

  // Nothing decisive. Expense is the safer default on a statement — but the low
  // score means the user is asked to confirm it.
  return (type: 'EXPENSE', confidence: 0.5);
}

/// Strips bank narration boilerplate to leave something merchant-shaped.
String? _extractRowMerchant(String description) {
  if (description.isEmpty) return null;

  final cleaned = description
      .replaceAll(
        _i(r'\b(pos|atm|purchase|payment|withdrawal|transfer|txn|ref|debit|'
            r'credit|card|visa|mastercard|dr|cr)\b'),
        ' ',
      )
      .replaceAll(RegExp(r'\b\d{4,}\b'), ' ')
      .replaceAll(RegExp(r'\*+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (cleaned.length < 3) return null;

  final letters = RegExp(r'[A-Za-z]').allMatches(cleaned).length;
  if (letters < 3) return null;

  final trimmed =
      cleaned.length > 60 ? cleaned.substring(0, 60).trim() : cleaned;
  return normaliseMerchant(trimmed);
}

String? _extractRowReference(String description) {
  final match = _i(r'\b(?:ref|txn|trn|trans)\.?\s*(?:no\.?|#)?\s*[:\-]?\s*'
          r'([A-Z0-9][A-Z0-9\-/]{4,24})\b')
      .firstMatch(description);
  if (match != null) return match.group(1);

  // A long digit run in bank narration is usually the transaction reference.
  final digits = RegExp(r'\b(\d{8,20})\b').firstMatch(description);
  return digits?.group(1);
}

String? _inferRowPaymentMethod(String description) {
  if (_i(r'\batm\b').hasMatch(description)) return 'CASH';
  if (_i(r'\bpos\b|\bvisa\b|\bmaster\s*card\b|\bcard\b').hasMatch(description)) {
    return 'DEBIT_CARD';
  }
  if (_i(r'\b(ceft|slips|rtgs|neft|transfer)\b').hasMatch(description)) {
    return 'BANK_TRANSFER';
  }
  if (_i(r'\b(standing\s*order|direct\s*debit)\b').hasMatch(description)) {
    return 'BANK_TRANSFER';
  }
  if (_i(r'\b(ib|internet\s*banking|online)\b').hasMatch(description)) {
    return 'ONLINE_BANKING';
  }
  return null;
}
