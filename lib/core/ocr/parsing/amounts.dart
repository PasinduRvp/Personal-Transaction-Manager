/// Amount recognition.
///
/// Every number on a receipt is a candidate amount, and picking the wrong one is
/// the most damaging mistake this pipeline can make. So amounts are found with
/// their surrounding label, scored, and the winner is reported with a confidence
/// the review screen can surface — rather than quietly taking the largest number
/// on the page.
library;

class FoundAmount {
  FoundAmount({
    required this.value,
    required this.raw,
    required this.line,
    required this.lineIndex,
    required this.label,
    this.score = 0,
  });

  /// Value in major units.
  final double value;

  /// The exact substring the value came from.
  final String raw;

  /// The whole line it appeared on, for display on the review screen.
  final String line;

  final int lineIndex;

  /// A label found next to it, e.g. `total`, lowercased.
  final String? label;

  /// 0–1 score of how likely this is the transaction's amount.
  double score;
}

class AmountSelection {
  const AmountSelection({
    required this.amount,
    required this.confidence,
    required this.alternatives,
  });

  final FoundAmount? amount;

  /// 0–1 confidence in the selection itself, not in the OCR of the digits.
  final double confidence;

  /// Other plausible amounts, strongest first, for the "did you mean" list.
  final List<FoundAmount> alternatives;
}

class _Label {
  const _Label(this.pattern, this.weight);
  final RegExp pattern;
  final double weight;
}

/// Labels that identify the figure a user would call "the amount", in priority
/// order. `subtotal` and the tax lines are deliberately *negative* signals.
final List<_Label> _totalLabels = [
  _Label(RegExp(r'\b(grand\s*total)\b', caseSensitive: false), 1.0),
  _Label(
      RegExp(r'\b(total\s*(?:amount|payable|due|paid))\b', caseSensitive: false),
      0.98),
  _Label(RegExp(r'\b(amount\s*(?:due|payable|paid))\b', caseSensitive: false),
      0.96),
  _Label(RegExp(r'\b(net\s*(?:total|amount|payable))\b', caseSensitive: false),
      0.94),
  _Label(RegExp(r'\b(balance\s*due)\b', caseSensitive: false), 0.92),
  _Label(RegExp(r'\b(total)\b', caseSensitive: false), 0.88),
  _Label(RegExp(r'\b(cash\s*(?:paid|tendered))\b', caseSensitive: false), 0.55),
  _Label(RegExp(r'\b(card\s*payment)\b', caseSensitive: false), 0.60),
];

final List<RegExp> _negativeLabels = [
  RegExp(r'\bsub\s*total\b', caseSensitive: false),
  RegExp(r'\b(vat|gst|tax|svc|service\s*charge|nbt)\b', caseSensitive: false),
  RegExp(r'\bchange\b', caseSensitive: false),
  RegExp(r'\bdiscount\b', caseSensitive: false),
  RegExp(r'\bsavings?\b', caseSensitive: false),
  RegExp(r'\bunit\s*price\b', caseSensitive: false),
  RegExp(r'\bqty\b', caseSensitive: false),
  RegExp(r'\bbalance\s*(?:forward|b/f|carried)\b', caseSensitive: false),
  RegExp(r'\bopening\s*balance\b', caseSensitive: false),
  RegExp(r'\bclosing\s*balance\b', caseSensitive: false),
];

class _CurrencyToken {
  const _CurrencyToken(this.pattern, this.code);
  final RegExp pattern;
  final String code;
}

/// Currency symbols and codes, mapped to ISO 4217.
final List<_CurrencyToken> _currencyTokens = [
  _CurrencyToken(RegExp(r'\b(lkr|rs\.?)\b|රු', caseSensitive: false), 'LKR'),
  _CurrencyToken(RegExp(r'\b(usd)\b|\$(?!\w)', caseSensitive: false), 'USD'),
  _CurrencyToken(RegExp(r'\b(eur)\b|€', caseSensitive: false), 'EUR'),
  _CurrencyToken(RegExp(r'\b(gbp)\b|£', caseSensitive: false), 'GBP'),
  _CurrencyToken(RegExp(r'\b(inr)\b|₹', caseSensitive: false), 'INR'),
  _CurrencyToken(RegExp(r'\b(aud)\b', caseSensitive: false), 'AUD'),
  _CurrencyToken(RegExp(r'\b(sgd)\b', caseSensitive: false), 'SGD'),
  _CurrencyToken(RegExp(r'\b(aed)\b', caseSensitive: false), 'AED'),
  _CurrencyToken(RegExp(r'\b(jpy)\b|¥', caseSensitive: false), 'JPY'),
];

/// Matches a money-shaped number: optional sign or bracket, digits with optional
/// grouping, optional decimal part. Requires either a grouping separator, a decimal
/// part, or four or more digits — a bare `15` on a receipt is far more likely a
/// quantity or a line number than a price.
final RegExp _amountPattern = RegExp(
  r'(?<![\w.])(-|\()?\s*(?:(?:lkr|usd|eur|gbp|inr|aud|sgd|aed|jpy|rs\.?|[$€£₹¥])\s*)?'
  r'(\d{1,3}(?:[,\s]\d{3})+(?:[.,]\d{1,2})?|\d+[.,]\d{2}|\d{4,})\s*(\)?)(?![\w])',
  caseSensitive: false,
);

String detectCurrency(String text, String fallback) {
  for (final token in _currencyTokens) {
    if (token.pattern.hasMatch(text)) return token.code;
  }
  return fallback;
}

/// Converts a money-shaped string to a number.
///
/// Decides which of `.` and `,` is the decimal separator from position rather than
/// locale: the right-most separator followed by one or two digits is the decimal
/// point, and everything else is grouping. That reads `8,450.00`, `8.450,00` and
/// `8450,00` correctly without being told the locale.
///
/// Also repairs the substitutions OCR makes on receipt fonts — `O` for zero, `l`
/// and `I` for one — because `845O` is never a real amount but `8450` is.
double? parseAmountToken(String token) {
  if (token.isEmpty) return null;

  // The token must already contain a real digit. Without this, the repair below
  // turns a word like "TOTAL" into "0" — a plausible-looking zero amount from text
  // that was never a number.
  if (!RegExp(r'[0-9]').hasMatch(token)) return null;

  final trimmed = token.trim();
  final negative =
      trimmed.startsWith('-') || (token.contains('(') && token.contains(')'));

  // Runs, not single characters. Lookaround is evaluated against the original
  // string, so a character-at-a-time rule saw the second `O` of `1,2OO.50` as
  // neither preceded nor followed by a digit and left it to be stripped — turning
  // 1200.50 into 120.50.
  var text = token
      .replaceAllMapped(
        RegExp(r'(?<=\d)[Oo]+|[Oo]+(?=\d)'),
        (m) => '0' * m.group(0)!.length,
      )
      .replaceAllMapped(
        RegExp(r'(?<=\d)[lI]+|[lI]+(?=\d)'),
        (m) => '1' * m.group(0)!.length,
      )
      .replaceAll(RegExp(r'[^\d.,]'), '');

  if (text.isEmpty) return null;

  final lastComma = text.lastIndexOf(',');
  final lastDot = text.lastIndexOf('.');
  final separatorIndex = lastComma > lastDot ? lastComma : lastDot;

  if (separatorIndex != -1) {
    final tail = text.length - separatorIndex - 1;
    final separatorCount = RegExp(r'[.,]').allMatches(text).length;

    // One or two trailing digits is a decimal part. So is three, when it is the
    // only separator: `10.005` is a unit price quoted to three places far more
    // often than a European-grouped 10,005, and the two readings are not equally
    // safe to get wrong — reading it as grouping inflates the figure a
    // thousandfold, while reading it as a decimal is out by half a cent.
    final isDecimal =
        tail == 1 || tail == 2 || (tail == 3 && separatorCount == 1);

    if (isDecimal) {
      final whole =
          text.substring(0, separatorIndex).replaceAll(RegExp(r'[.,]'), '');
      final fraction = text.substring(separatorIndex + 1);
      text = '$whole.$fraction';
    } else {
      text = text.replaceAll(RegExp(r'[.,]'), '');
    }
  }

  final value = double.tryParse(text);
  if (value == null || !value.isFinite) return null;

  // Rounded to cents, matching how the amount will be stored.
  final rounded = (value.abs() * 100).round() / 100;
  return negative ? -rounded : rounded;
}

/// Finds every money-shaped number in the text, with its context.
List<FoundAmount> findAmounts(List<String> lines) {
  final results = <FoundAmount>[];

  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    final line = lines[lineIndex];
    final hasCurrencyToken =
        _currencyTokens.any((t) => t.pattern.hasMatch(line));

    for (final match in _amountPattern.allMatches(line)) {
      final raw = match.group(0)!.trim();
      final value = parseAmountToken(raw);
      if (value == null || value == 0) continue;

      // Guard against year-like bare integers being read as money.
      final digits = match.group(2) ?? '';
      final bareInteger = !RegExp(r'[.,]').hasMatch(digits);
      if (bareInteger && !hasCurrencyToken && value >= 1900 && value <= 2100) {
        continue;
      }

      results.add(FoundAmount(
        value: value,
        raw: raw,
        line: line,
        lineIndex: lineIndex,
        label: _findLabel(line),
      ));
    }
  }

  return _scoreAmounts(results, lines.length);
}

String? _findLabel(String line) {
  for (final label in _totalLabels) {
    final match = label.pattern.firstMatch(line);
    if (match != null) {
      return match.group(1)!.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    }
  }
  return null;
}

/// Scores each amount on how likely it is to be "the" amount.
///
/// The signals, roughly in order of strength: an explicit total label; sitting near
/// the bottom of a receipt, where totals live; having two decimal places; and not
/// being labelled as tax, subtotal or change.
List<FoundAmount> _scoreAmounts(List<FoundAmount> amounts, int lineCount) {
  var maxValue = 0.0;
  for (final amount in amounts) {
    final absolute = amount.value.abs();
    if (absolute > maxValue) maxValue = absolute;
  }

  for (final amount in amounts) {
    var score = 0.2;

    for (final label in _totalLabels) {
      if (label.pattern.hasMatch(amount.line)) {
        if (label.weight > score) score = label.weight;
        break;
      }
    }

    if (_negativeLabels.any((p) => p.hasMatch(amount.line))) {
      score -= 0.55;
    }

    // Receipts put the total near the end.
    if (lineCount > 4) {
      final position = amount.lineIndex / (lineCount - 1);
      if (position > 0.6) score += 0.12;
      if (position > 0.85) score += 0.05;
    }

    if (RegExp(r'[.,]\d{2}\b').hasMatch(amount.raw)) score += 0.08;

    // The largest number on a receipt is usually the total, but only as a
    // tie-breaker — an unlabelled maximum is a weak signal, not a strong one.
    if (maxValue > 0 && amount.value.abs() == maxValue) score += 0.1;

    amount.score = score.clamp(0.0, 1.0);
  }

  amounts.sort((a, b) => b.score.compareTo(a.score));
  return amounts;
}

/// Chooses the transaction amount.
///
/// Returns a null amount rather than a guess when nothing scores plausibly. The
/// review screen then blocks confirmation until the user types the figure, which is
/// the correct outcome: an unreadable receipt should cost ten seconds of typing,
/// not produce a wrong number in a ledger.
AmountSelection selectAmount(List<String> lines) {
  final amounts = findAmounts(lines);
  if (amounts.isEmpty) {
    return const AmountSelection(
      amount: null,
      confidence: 0,
      alternatives: [],
    );
  }

  final best = amounts.first;
  final runnerUp = amounts.length > 1 ? amounts[1] : null;

  // Confidence reflects both the winner's own score and how clearly it beat the
  // next candidate: two equally plausible totals means low confidence.
  var confidence = best.score;
  if (runnerUp != null) {
    final margin = best.score - runnerUp.score;
    if (margin < 0.1) {
      confidence *= 0.75;
    } else if (margin < 0.25) {
      confidence *= 0.9;
    }
  }

  if (best.label == null) confidence *= 0.8;

  return AmountSelection(
    amount: best,
    confidence:
        double.parse(confidence.clamp(0.0, 1.0).toStringAsFixed(4)),
    alternatives: amounts.skip(1).take(4).toList(growable: false),
  );
}
