import 'package:intl/intl.dart';

import '../constants/currencies.dart';

/// An exact monetary amount.
///
/// Money is stored as an integer number of minor units (cents) so that sums,
/// splits and budget comparisons are exact. Binary floating point cannot
/// represent values like `0.10` precisely, and accumulating `double` amounts
/// across hundreds of transactions produces visible rounding drift in a
/// finance app. Every arithmetic operation in Finora goes through this class.
class Money implements Comparable<Money> {
  const Money._(this.minorUnits, this.currency);

  /// Amount in minor units (e.g. cents). May be negative.
  final int minorUnits;

  /// ISO 4217 code, uppercase.
  final String currency;

  static const String _defaultCurrency = 'LKR';

  factory Money.zero([String currency = _defaultCurrency]) =>
      Money._(0, currency.toUpperCase());

  /// Builds from minor units directly.
  factory Money.fromMinorUnits(int minorUnits,
          [String currency = _defaultCurrency]) =>
      Money._(minorUnits, currency.toUpperCase());

  /// Builds from a major-unit number (what the database `numeric` column and
  /// the UI both speak). Uses half-away-from-zero rounding, the convention
  /// used for currency.
  factory Money.fromMajor(num major, [String currency = _defaultCurrency]) {
    final code = currency.toUpperCase();
    final scale = _scaleFor(code);
    final scaled = major * scale;
    final rounded = scaled < 0 ? -(-scaled).round() : scaled.round();
    return Money._(rounded, code);
  }

  /// Parses user input. Tolerates grouping separators, currency symbols and
  /// the OCR habit of confusing `O`/`o` with zero. Returns null when the text
  /// contains no recognisable number.
  static Money? tryParse(String? input, [String currency = _defaultCurrency]) {
    if (input == null) return null;
    var text = input.trim();
    if (text.isEmpty) return null;

    // The input must already contain a real digit. Without this guard the OCR
    // repair below turns a word like "TOTAL" into "0" — a plain-looking zero
    // amount from text that was never a number at all, which is exactly the
    // kind of silent wrong figure this class exists to prevent.
    if (!text.contains(RegExp('[0-9]'))) return null;

    final negative = text.startsWith('-') ||
        (text.startsWith('(') && text.endsWith(')'));

    // Normalise the substitutions OCR makes on receipt fonts, then strip
    // everything that cannot be part of a number.
    text = text
        .replaceAll(RegExp('[Oo]'), '0')
        .replaceAll(RegExp('[lI]'), '1')
        .replaceAll(RegExp(r'[^0-9.,]'), '');
    if (text.isEmpty) return null;

    text = _normaliseDecimalSeparator(text);

    final value = double.tryParse(text);
    if (value == null) return null;
    final money = Money.fromMajor(value, currency);
    return negative ? -money : money;
  }

  /// Decides whether `,` or `.` is the decimal separator and returns a string
  /// `double.parse` understands. Handles `8,450.00`, `8.450,00` and `8450,00`.
  static String _normaliseDecimalSeparator(String text) {
    final lastComma = text.lastIndexOf(',');
    final lastDot = text.lastIndexOf('.');

    if (lastComma == -1 && lastDot == -1) return text;

    // The right-most separator is the decimal one when it is followed by one or
    // two digits — and also by three, when it is the only separator in the
    // string. `10.005` is a price quoted to three places far more often than it
    // is a European-grouped 10,005, and the two readings are not equally safe to
    // get wrong: reading it as grouping inflates the figure a thousandfold, while
    // reading it as a decimal is out by half a cent.
    //
    // This rule is deliberately identical to the one in the Cloud Functions'
    // `parseAmountToken`. The same string has to produce the same number whether
    // the app parses it or the OCR pipeline does, or a figure would change as it
    // crossed the boundary.
    final decimalIndex = lastComma > lastDot ? lastComma : lastDot;
    final tail = text.length - decimalIndex - 1;
    final separatorCount =
        RegExp(r'[.,]').allMatches(text).length;

    if (tail == 1 || tail == 2 || (tail == 3 && separatorCount == 1)) {
      final intPart =
          text.substring(0, decimalIndex).replaceAll(RegExp(r'[.,]'), '');
      final fracPart = text.substring(decimalIndex + 1);
      return '$intPart.$fracPart';
    }
    return text.replaceAll(RegExp(r'[.,]'), '');
  }

  static int _scaleFor(String currency) {
    final decimals = Currencies.byCode(currency).decimals;
    var scale = 1;
    for (var i = 0; i < decimals; i++) {
      scale *= 10;
    }
    return scale;
  }

  int get _scale => _scaleFor(currency);

  /// The amount as a major-unit double. Use only for display and for writing
  /// to the database — never for arithmetic.
  double get amount => minorUnits / _scale;

  bool get isZero => minorUnits == 0;
  bool get isNegative => minorUnits < 0;
  bool get isPositive => minorUnits > 0;

  Money get abs => Money._(minorUnits.abs(), currency);

  Money operator -() => Money._(-minorUnits, currency);

  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money._(minorUnits + other.minorUnits, currency);
  }

  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money._(minorUnits - other.minorUnits, currency);
  }

  /// Scales the amount, rounding to the nearest minor unit.
  Money operator *(num factor) {
    final scaled = minorUnits * factor;
    final rounded = scaled < 0 ? -(-scaled).round() : scaled.round();
    return Money._(rounded, currency);
  }

  bool operator >(Money other) {
    _assertSameCurrency(other);
    return minorUnits > other.minorUnits;
  }

  bool operator >=(Money other) {
    _assertSameCurrency(other);
    return minorUnits >= other.minorUnits;
  }

  bool operator <(Money other) {
    _assertSameCurrency(other);
    return minorUnits < other.minorUnits;
  }

  bool operator <=(Money other) {
    _assertSameCurrency(other);
    return minorUnits <= other.minorUnits;
  }

  /// This amount as a percentage of [total]. Returns 0 when [total] is zero so
  /// callers never divide by zero when rendering progress bars.
  double percentOf(Money total) {
    if (total.minorUnits == 0) return 0;
    return (minorUnits / total.minorUnits) * 100;
  }

  /// Splits the amount into [parts] shares that sum back exactly to this
  /// amount; the remainder cents are distributed over the first shares.
  List<Money> splitEvenly(int parts) {
    if (parts <= 0) return const [];
    final base = minorUnits ~/ parts;
    var remainder = minorUnits.remainder(parts).abs();
    final sign = minorUnits.isNegative ? -1 : 1;
    return List<Money>.generate(parts, (i) {
      final extra = remainder > 0 ? sign : 0;
      if (remainder > 0) remainder--;
      return Money._(base + extra, currency);
    });
  }

  void _assertSameCurrency(Money other) {
    if (other.currency != currency) {
      throw ArgumentError(
        'Cannot combine $currency with ${other.currency}. '
        'Convert to a common currency first.',
      );
    }
  }

  /// Formatted with the currency symbol, e.g. `Rs. 8,450.00`.
  String format({bool showSymbol = true, bool showDecimals = true}) {
    final info = Currencies.byCode(currency);
    final decimals = showDecimals ? info.decimals : 0;
    final pattern = NumberFormat.decimalPatternDigits(
      decimalDigits: decimals,
    );
    final formatted = pattern.format(amount.abs());
    final sign = isNegative ? '-' : '';
    if (!showSymbol) return '$sign$formatted';
    return '$sign${info.symbol} $formatted';
  }

  /// Formatted with an explicit `+`/`-` sign, for transaction rows.
  String formatSigned() {
    final body = format();
    if (isNegative) return body;
    return '+$body';
  }

  /// Short form for chart axes and dense tiles: `Rs. 8.5K`, `Rs. 1.2M`.
  String formatCompact({bool showSymbol = true}) {
    final info = Currencies.byCode(currency);
    final value = amount.abs();
    final sign = isNegative ? '-' : '';
    final prefix = showSymbol ? '${info.symbol} ' : '';
    String body;
    if (value >= 1000000000) {
      body = '${(value / 1000000000).toStringAsFixed(1)}B';
    } else if (value >= 1000000) {
      body = '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      body = '${(value / 1000).toStringAsFixed(1)}K';
    } else {
      body = value.toStringAsFixed(info.decimals);
    }
    return '$sign$prefix$body';
  }

  /// Plain editable text for a form field: `8450.00`, no symbol or grouping.
  String toEditableString() =>
      amount.toStringAsFixed(Currencies.byCode(currency).decimals);

  /// Value written to a `numeric(14,2)` column.
  double toJson() => amount;

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minorUnits == minorUnits &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(minorUnits, currency);

  @override
  String toString() => '${format(showSymbol: false)} $currency';
}

/// Sums an iterable of [Money]. All entries must share a currency; an empty
/// iterable yields zero in [currency].
extension MoneyIterable on Iterable<Money> {
  Money sum([String currency = 'LKR']) {
    if (isEmpty) return Money.zero(currency);
    return reduce((a, b) => a + b);
  }
}
