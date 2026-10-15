import 'package:finora/core/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';

/// Money is the foundation every financial figure in the app rests on, so these
/// tests are deliberately thorough about the cases that make floating point
/// unsuitable for currency in the first place.
void main() {
  group('Money construction', () {
    test('fromMajor stores exact minor units', () {
      expect(Money.fromMajor(10).minorUnits, 1000);
      expect(Money.fromMajor(0.01).minorUnits, 1);
      expect(Money.fromMajor(8450.55).minorUnits, 845055);
    });

    test('fromMajor rounds half away from zero, the currency convention', () {
      expect(Money.fromMajor(10.005).minorUnits, 1001);
      expect(Money.fromMajor(-10.005).minorUnits, -1001);
      expect(Money.fromMajor(10.004).minorUnits, 1000);
    });

    test('honours currencies with no minor unit', () {
      final yen = Money.fromMajor(1500, 'JPY');
      expect(yen.minorUnits, 1500);
      expect(yen.amount, 1500);
    });

    test('normalises the currency code to uppercase', () {
      expect(Money.fromMajor(1, 'lkr').currency, 'LKR');
    });
  });

  group('Money arithmetic', () {
    test('adds without floating point drift', () {
      // 0.1 + 0.2 != 0.3 in binary floating point; in minor units it is exact.
      final sum = Money.fromMajor(0.1) + Money.fromMajor(0.2);
      expect(sum, Money.fromMajor(0.3));
      expect(sum.minorUnits, 30);
    });

    test('accumulating many small amounts stays exact', () {
      var total = Money.zero();
      for (var i = 0; i < 1000; i++) {
        total += Money.fromMajor(0.01);
      }
      expect(total.minorUnits, 1000);
      expect(total, Money.fromMajor(10));
    });

    test('subtracts and can go negative', () {
      final result = Money.fromMajor(100) - Money.fromMajor(250);
      expect(result.minorUnits, -15000);
      expect(result.isNegative, isTrue);
    });

    test('scales and rounds to the nearest minor unit', () {
      expect((Money.fromMajor(100) * 0.155).minorUnits, 1550);
      expect((Money.fromMajor(10) * (1 / 3)).minorUnits, 333);
    });

    test('refuses to combine different currencies', () {
      expect(
        () => Money.fromMajor(10, 'LKR') + Money.fromMajor(10, 'USD'),
        throwsArgumentError,
      );
    });

    test('compares only within a currency', () {
      expect(Money.fromMajor(10) > Money.fromMajor(5), isTrue);
      expect(Money.fromMajor(5) <= Money.fromMajor(5), isTrue);
      expect(
        () => Money.fromMajor(10, 'LKR') > Money.fromMajor(5, 'USD'),
        throwsArgumentError,
      );
    });
  });

  group('Money.percentOf', () {
    test('computes a share', () {
      expect(
        Money.fromMajor(2250).percentOf(Money.fromMajor(3000)),
        closeTo(75, 0.0001),
      );
    });

    test('returns zero rather than dividing by zero', () {
      // A budget of zero must not produce infinity in a progress bar.
      expect(Money.fromMajor(100).percentOf(Money.zero()), 0);
    });
  });

  group('Money.splitEvenly', () {
    test('splits exactly when divisible', () {
      final parts = Money.fromMajor(90).splitEvenly(3);
      expect(parts.map((p) => p.minorUnits), [3000, 3000, 3000]);
    });

    test('distributes the remainder so the parts sum to the whole', () {
      final parts = Money.fromMajor(10).splitEvenly(3);
      expect(parts.map((p) => p.minorUnits), [334, 333, 333]);
      expect(parts.reduce((a, b) => a + b), Money.fromMajor(10));
    });

    test('keeps the sum exact for a negative amount', () {
      final parts = (-Money.fromMajor(10)).splitEvenly(3);
      expect(parts.reduce((a, b) => a + b), -Money.fromMajor(10));
    });

    test('returns nothing for a non-positive part count', () {
      expect(Money.fromMajor(10).splitEvenly(0), isEmpty);
    });
  });

  group('Money.tryParse', () {
    test('reads plain and grouped numbers', () {
      expect(Money.tryParse('8450')?.minorUnits, 845000);
      expect(Money.tryParse('8,450.00')?.minorUnits, 845000);
      expect(Money.tryParse('1,234,567.89')?.minorUnits, 123456789);
    });

    test('reads European grouping', () {
      expect(Money.tryParse('8.450,00')?.minorUnits, 845000);
      expect(Money.tryParse('8450,50')?.minorUnits, 845050);
    });

    test('strips currency symbols', () {
      expect(Money.tryParse('Rs. 8,450.00')?.minorUnits, 845000);
      expect(Money.tryParse(r'$1,299.99')?.minorUnits, 129999);
    });

    test('repairs the letter-for-digit confusions OCR makes', () {
      // A thermal-printer zero is frequently read as a capital O.
      expect(Money.tryParse('845O')?.minorUnits, 845000);
      expect(Money.tryParse('1,2OO.50')?.minorUnits, 120050);
    });

    test('treats brackets and a leading minus as negative', () {
      expect(Money.tryParse('(1,500.00)')?.minorUnits, -150000);
      expect(Money.tryParse('-250.75')?.minorUnits, -25075);
    });

    test('returns null when there is no number', () {
      expect(Money.tryParse('TOTAL'), isNull);
      expect(Money.tryParse(''), isNull);
      expect(Money.tryParse(null), isNull);
    });
  });

  group('Money formatting', () {
    test('formats with the currency symbol and grouping', () {
      expect(Money.fromMajor(8450).format(), 'Rs. 8,450.00');
      expect(Money.fromMajor(8450, 'USD').format(), r'$ 8,450.00');
    });

    test('places the sign before the symbol for negatives', () {
      expect(Money.fromMajor(-8450).format(), '-Rs. 8,450.00');
    });

    test('omits decimals for a zero-decimal currency', () {
      expect(Money.fromMajor(1500, 'JPY').format(), '¥ 1,500');
    });

    test('formats compactly for chart axes', () {
      expect(Money.fromMajor(8500).formatCompact(), 'Rs. 8.5K');
      expect(Money.fromMajor(1250000).formatCompact(), 'Rs. 1.3M');
      expect(Money.fromMajor(450).formatCompact(), 'Rs. 450.00');
    });

    test('produces an editable string with no symbol or grouping', () {
      expect(Money.fromMajor(8450.5).toEditableString(), '8450.50');
    });

    test('round-trips through the editable form', () {
      final original = Money.fromMajor(12345.67);
      expect(Money.tryParse(original.toEditableString()), original);
    });
  });

  group('Money JSON', () {
    test('serialises as a major-unit double for a numeric column', () {
      expect(Money.fromMajor(8450.55).toJson(), 8450.55);
    });

    test('survives a database round trip', () {
      final original = Money.fromMajor(999999.99);
      expect(Money.fromMajor(original.toJson()), original);
    });
  });

  group('MoneyIterable.sum', () {
    test('sums a list exactly', () {
      final amounts = [
        Money.fromMajor(6000),
        Money.fromMajor(2500),
        Money.fromMajor(1500),
      ];
      expect(amounts.sum(), Money.fromMajor(10000));
    });

    test('returns zero for an empty list rather than throwing', () {
      expect(<Money>[].sum('USD'), Money.zero('USD'));
    });
  });

  group('Money.tryParse agrees with the OCR pipeline', () {
    // These cases are the Dart half of a contract: `parseAmountToken` in
    // functions/src/parsing/amounts.ts must read the same strings the same way.
    // A figure that changed as it crossed from the pipeline to the app would be
    // the worst kind of bug here — silent, and about money.

    test('a lone three-decimal separator is a decimal, not grouping', () {
      // Reading this as 10,005 would inflate the amount a thousandfold. Half a
      // cent of rounding is the safer error by an enormous margin.
      expect(Money.tryParse('10.005')?.amount, closeTo(10.01, 0.0001));
      expect(Money.tryParse('10,005')?.amount, closeTo(10.01, 0.0001));
    });

    test('grouping is still grouping when there are two separators', () {
      expect(Money.tryParse('8.450,00')?.amount, closeTo(8450, 0.0001));
      expect(Money.tryParse('8,450.00')?.amount, closeTo(8450, 0.0001));
      expect(Money.tryParse('1,234,567.89')?.amount, closeTo(1234567.89, 0.0001));
    });

    test('a run of OCR letters is repaired, not half-repaired', () {
      // `1,2OO.50` must become 1200.50. An earlier version of the equivalent
      // repair in the pipeline fixed the first O and dropped the second, giving
      // 120.50.
      expect(Money.tryParse('1,2OO.50')?.amount, closeTo(1200.5, 0.0001));
      expect(Money.tryParse('845O')?.amount, closeTo(8450, 0.0001));
      expect(Money.tryParse('l0.00')?.amount, closeTo(10, 0.0001));
    });

    test('text with no digit in it is not an amount', () {
      expect(Money.tryParse('TOTAL'), isNull);
      expect(Money.tryParse('OOO'), isNull);
      expect(Money.tryParse(''), isNull);
    });
  });
}
