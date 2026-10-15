/// The parser's output types.
///
/// Ported from the Cloud Functions' TypeScript when the backend moved to the free
/// plan and OCR became an on-device job. The behaviour is identical — the same 45
/// cases that tested the TypeScript test this, which is the point of keeping
/// parsing separate from recognition in the first place.
library;

/// A proposed transaction, before anything is written.
///
/// Every field is optional except the type, because the parser must be able to say
/// "I did not find this" instead of filling a financial field with a guess.
/// [fieldConfidence] carries a 0–1 score per field so the review screen can flag
/// exactly the values that need a human eye.
class ParsedCandidate {
  const ParsedCandidate({
    required this.transactionType,
    required this.amount,
    required this.currency,
    required this.merchant,
    required this.description,
    required this.transactionDate,
    required this.suggestedCategoryName,
    required this.paymentMethod,
    required this.referenceNumber,
    required this.confidence,
    required this.fieldConfidence,
    required this.pageNumber,
    required this.rawLine,
    required this.sortOrder,
  });

  /// `EXPENSE`, `INCOME` or `TRANSFER`.
  final String transactionType;

  /// In major units, or null when none could be read. Never defaulted to zero: a
  /// zero would look like a figure that had been found.
  final double? amount;

  final String currency;
  final String? merchant;
  final String? description;

  /// ISO `yyyy-MM-dd`.
  final String? transactionDate;

  /// A category *name*. The caller maps it to one of the user's own categories;
  /// the parser never invents a category id.
  final String? suggestedCategoryName;

  final String? paymentMethod;
  final String? referenceNumber;

  /// Mean of the per-field scores that are present.
  final double? confidence;
  final Map<String, double> fieldConfidence;

  final int? pageNumber;

  /// The source line, shown beneath the fields on the review screen so the user
  /// can see what the figure was read from.
  final String? rawLine;

  final int sortOrder;
}

class ParseResult {
  const ParseResult({
    required this.documentKind,
    required this.classificationConfidence,
    required this.candidates,
    required this.signals,
  });

  final String documentKind;
  final double classificationConfidence;
  final List<ParsedCandidate> candidates;

  /// What the classifier matched on, kept for the "why did it decide that" panel.
  final List<String> signals;
}

class ParseOptions {
  const ParseOptions({
    required this.defaultCurrency,
    this.preferDayFirst = true,
    this.pageNumbers = const [],
  });

  final String defaultCurrency;

  /// Day-first date reading, which is the convention in Sri Lanka and most of the
  /// world outside the United States.
  final bool preferDayFirst;

  final List<int> pageNumbers;
}

/// Normalises text into trimmed, non-empty lines with collapsed whitespace.
List<String> toLines(String text) => text
    .split(RegExp(r'\r?\n'))
    .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
    .where((line) => line.isNotEmpty)
    .toList(growable: false);

double? meanOf(Iterable<double> values) {
  final list = values.toList();
  if (list.isEmpty) return null;
  final sum = list.reduce((a, b) => a + b);
  return double.parse((sum / list.length).toStringAsFixed(4));
}
