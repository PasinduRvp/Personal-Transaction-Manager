/// A small, offline currency table. Kept local so formatting never depends on
/// a network call.
class CurrencyInfo {
  const CurrencyInfo(this.code, this.name, this.symbol, {this.decimals = 2});

  final String code;
  final String name;
  final String symbol;
  final int decimals;
}

class Currencies {
  const Currencies._();

  static const CurrencyInfo fallback =
      CurrencyInfo('LKR', 'Sri Lankan Rupee', 'Rs.');

  static const List<CurrencyInfo> all = [
    CurrencyInfo('LKR', 'Sri Lankan Rupee', 'Rs.'),
    CurrencyInfo('USD', 'US Dollar', r'$'),
    CurrencyInfo('EUR', 'Euro', '€'),
    CurrencyInfo('GBP', 'British Pound', '£'),
    CurrencyInfo('INR', 'Indian Rupee', '₹'),
    CurrencyInfo('AUD', 'Australian Dollar', r'A$'),
    CurrencyInfo('CAD', 'Canadian Dollar', r'C$'),
    CurrencyInfo('SGD', 'Singapore Dollar', r'S$'),
    CurrencyInfo('AED', 'UAE Dirham', 'AED'),
    CurrencyInfo('JPY', 'Japanese Yen', '¥', decimals: 0),
  ];

  static CurrencyInfo byCode(String? code) {
    if (code == null) return fallback;
    final upper = code.toUpperCase();
    for (final c in all) {
      if (c.code == upper) return c;
    }
    return CurrencyInfo(upper, upper, upper);
  }

  static String symbolFor(String? code) => byCode(code).symbol;
}
