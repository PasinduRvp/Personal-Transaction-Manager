/// Date recognition.
///
/// `15/09/2026` and `09/15/2026` are the same six characters in a different order,
/// and getting it wrong silently files a transaction in the wrong month. So every
/// parse reports a confidence, and a genuinely ambiguous date is returned with a
/// low one so the review screen asks the user to check it.
library;

class FoundDate {
  const FoundDate({
    required this.iso,
    required this.raw,
    required this.line,
    required this.lineIndex,
    required this.confidence,
    required this.ambiguous,
  });

  /// ISO `yyyy-MM-dd`.
  final String iso;

  /// The substring it was read from.
  final String raw;
  final String line;
  final int lineIndex;

  /// 0–1. Below about 0.8 the review screen flags the field.
  final double confidence;

  /// True when day/month order had to be assumed rather than deduced.
  final bool ambiguous;
}

const Map<String, int> _monthNames = {
  'jan': 1, 'january': 1,
  'feb': 2, 'february': 2,
  'mar': 3, 'march': 3,
  'apr': 4, 'april': 4,
  'may': 5,
  'jun': 6, 'june': 6,
  'jul': 7, 'july': 7,
  'aug': 8, 'august': 8,
  'sep': 9, 'sept': 9, 'september': 9,
  'oct': 10, 'october': 10,
  'nov': 11, 'november': 11,
  'dec': 12, 'december': 12,
};

/// Labels that mark the transaction date rather than some other date.
final List<RegExp> _dateLabels = [
  RegExp(r'\b(transaction\s*date)\b', caseSensitive: false),
  RegExp(r'\b(date\s*of\s*(?:purchase|transaction|issue))\b',
      caseSensitive: false),
  RegExp(r'\b(invoice\s*date)\b', caseSensitive: false),
  RegExp(r'\b(payment\s*date)\b', caseSensitive: false),
  RegExp(r'\b(date)\b', caseSensitive: false),
];

/// Labels whose date is explicitly *not* the transaction date.
final List<RegExp> _negativeDateLabels = [
  RegExp(r'\bdue\s*date\b', caseSensitive: false),
  RegExp(r'\bexpiry\b', caseSensitive: false),
  RegExp(r'\bexp\.?\s*date\b', caseSensitive: false),
  RegExp(r'\bvalid\s*(?:until|till|thru)\b', caseSensitive: false),
  RegExp(r'\bstatement\s*period\b', caseSensitive: false),
  RegExp(r'\bprinted\s*on\b', caseSensitive: false),
];

final RegExp _numericDate =
    RegExp(r'\b(\d{1,4})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{2,4})\b');

final RegExp _textualDateDmy = RegExp(
    r'\b(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]{3,9})\.?,?\s+(\d{2,4})\b',
    caseSensitive: false);

final RegExp _textualDateMdy = RegExp(
    r'\b([A-Za-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{2,4})\b',
    caseSensitive: false);

class DateParseOptions {
  const DateParseOptions({
    this.preferDayFirst = true,
    this.notAfter,
    this.notBefore,
  });

  /// Whether an ambiguous `03/04/2026` should be read as 3 April rather than
  /// 4 March. Day-first by default, the convention across most of the world
  /// including Sri Lanka.
  final bool preferDayFirst;

  /// Dates after this are rejected as misreads. Defaults to today plus two days.
  final DateTime? notAfter;

  /// Dates before this are rejected. Defaults to twenty years ago.
  final DateTime? notBefore;
}

class ParsedDate {
  const ParsedDate(this.iso, this.confidence, this.ambiguous);
  final String iso;
  final double confidence;
  final bool ambiguous;
}

/// Parses one date string. Returns null when it is not a valid calendar date.
ParsedDate? parseDateToken(
  String token, [
  DateParseOptions options = const DateParseOptions(),
]) {
  final trimmed = token.trim();

  // --- yyyy-mm-dd and dd/mm/yyyy family ------------------------------------
  final numeric =
      RegExp(r'^(\d{1,4})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{2,4})$')
          .firstMatch(trimmed);

  if (numeric != null) {
    final first = numeric.group(1)!;
    final a = int.parse(first);
    final b = int.parse(numeric.group(2)!);
    final c = int.parse(numeric.group(3)!);

    // An unambiguous four-digit leading year.
    if (first.length == 4) {
      return _finalise(a, b, c, 0.95, false, options);
    }

    final year = _expandYear(c);

    // Day > 12 proves day-first; month position > 12 proves month-first.
    if (a > 12 && b <= 12) return _finalise(year, b, a, 0.95, false, options);
    if (b > 12 && a <= 12) return _finalise(year, a, b, 0.95, false, options);

    // Both at most 12: genuinely ambiguous. Pick the convention and say so.
    if (options.preferDayFirst) {
      return _finalise(year, b, a, 0.62, true, options);
    }
    return _finalise(year, a, b, 0.62, true, options);
  }

  // --- 15 Sep 2026 ---------------------------------------------------------
  final dmy = RegExp(
          r'^(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]{3,9})\.?,?\s+(\d{2,4})$',
          caseSensitive: false)
      .firstMatch(trimmed);

  if (dmy != null) {
    final month = _monthNames[dmy.group(2)!.toLowerCase()];
    if (month != null) {
      return _finalise(
        _expandYear(int.parse(dmy.group(3)!)),
        month,
        int.parse(dmy.group(1)!),
        0.97,
        false,
        options,
      );
    }
  }

  // --- Sep 15, 2026 --------------------------------------------------------
  final mdy = RegExp(
          r'^([A-Za-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{2,4})$',
          caseSensitive: false)
      .firstMatch(trimmed);

  if (mdy != null) {
    final month = _monthNames[mdy.group(1)!.toLowerCase()];
    if (month != null) {
      return _finalise(
        _expandYear(int.parse(mdy.group(3)!)),
        month,
        int.parse(mdy.group(2)!),
        0.97,
        false,
        options,
      );
    }
  }

  return null;
}

int _expandYear(int value) {
  if (value >= 1000) return value;
  // A two-digit year on a financial document is in the recent past or the near
  // future, never 1926.
  final currentTwoDigit = DateTime.now().year % 100;
  return value <= currentTwoDigit + 5 ? 2000 + value : 1900 + value;
}

ParsedDate? _finalise(
  int year,
  int month,
  int day,
  double confidence,
  bool ambiguous,
  DateParseOptions options,
) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;

  // Reject dates the calendar does not have, such as 31 February — a real misread
  // rather than an unusual date.
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }

  final notAfter =
      options.notAfter ?? DateTime.now().toUtc().add(const Duration(days: 2));
  final notBefore =
      options.notBefore ?? DateTime.utc(DateTime.now().year - 20, 1, 1);

  if (date.isAfter(notAfter) || date.isBefore(notBefore)) return null;

  final iso = '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  return ParsedDate(iso, confidence, ambiguous);
}

/// Finds every date in the document, best candidate first.
List<FoundDate> findDates(
  List<String> lines, [
  DateParseOptions options = const DateParseOptions(),
]) {
  final results = <FoundDate>[];

  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    final line = lines[lineIndex];

    for (final pattern in [_numericDate, _textualDateDmy, _textualDateMdy]) {
      for (final match in pattern.allMatches(line)) {
        final raw = match.group(0)!;
        final parsed = parseDateToken(raw, options);
        if (parsed == null) continue;

        var confidence = parsed.confidence;

        // A labelled date beats an unlabelled one; a due date or an expiry is not
        // the transaction date at all.
        if (_negativeDateLabels.any((p) => p.hasMatch(line))) {
          confidence *= 0.35;
        } else if (_dateLabels.any((p) => p.hasMatch(line))) {
          confidence = (confidence + 0.05).clamp(0.0, 1.0);
        }

        // Receipts print the date near the top.
        if (lines.length > 6 && lineIndex / lines.length < 0.35) {
          confidence = (confidence + 0.03).clamp(0.0, 1.0);
        }

        results.add(FoundDate(
          iso: parsed.iso,
          raw: raw.trim(),
          line: line,
          lineIndex: lineIndex,
          confidence: double.parse(confidence.toStringAsFixed(4)),
          ambiguous: parsed.ambiguous,
        ));
      }
    }
  }

  // De-duplicate identical dates, keeping the most confident occurrence.
  final byIso = <String, FoundDate>{};
  for (final found in results) {
    final existing = byIso[found.iso];
    if (existing == null || found.confidence > existing.confidence) {
      byIso[found.iso] = found;
    }
  }

  final sorted = byIso.values.toList()
    ..sort((a, b) => b.confidence.compareTo(a.confidence));
  return sorted;
}

/// The single best date, or null when the document contains none.
FoundDate? selectDate(
  List<String> lines, [
  DateParseOptions options = const DateParseOptions(),
]) {
  final dates = findDates(lines, options);
  return dates.isEmpty ? null : dates.first;
}
