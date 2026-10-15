import 'package:finora/core/constants/enums.dart';
import 'package:finora/core/utils/app_date_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Day and month boundaries', () {
    test('startOfDay strips the time', () {
      final result = AppDateUtils.startOfDay(DateTime(2026, 9, 15, 14, 32, 45));
      expect(result, DateTime(2026, 9, 15));
    });

    test('endOfDay is the last millisecond', () {
      final result = AppDateUtils.endOfDay(DateTime(2026, 9, 15, 8));
      expect(result, DateTime(2026, 9, 15, 23, 59, 59, 999));
    });

    test('weeks start on Monday', () {
      // 2026-09-15 is a Tuesday.
      expect(
        AppDateUtils.startOfWeek(DateTime(2026, 9, 15)),
        DateTime(2026, 9, 14),
      );
      // A Monday is already the start of its own week.
      expect(
        AppDateUtils.startOfWeek(DateTime(2026, 9, 14)),
        DateTime(2026, 9, 14),
      );
      // A Sunday belongs to the week that began the previous Monday.
      expect(
        AppDateUtils.startOfWeek(DateTime(2026, 9, 20)),
        DateTime(2026, 9, 14),
      );
    });

    test('month bounds cover the whole month', () {
      expect(
        AppDateUtils.startOfMonth(DateTime(2026, 9, 15)),
        DateTime(2026, 9),
      );
      expect(
        AppDateUtils.endOfMonth(DateTime(2026, 9, 15)),
        DateTime(2026, 9, 30, 23, 59, 59, 999),
      );
    });

    test('daysInMonth handles February in a leap year', () {
      expect(AppDateUtils.daysInMonth(DateTime(2026, 2)), 28);
      expect(AppDateUtils.daysInMonth(DateTime(2028, 2)), 29);
      expect(AppDateUtils.daysInMonth(DateTime(2026, 12)), 31);
    });
  });

  group('DateRange', () {
    test('counts days inclusively', () {
      final range = DateRange(DateTime(2026, 9), DateTime(2026, 9, 30));
      expect(range.dayCount, 30);

      final single = DateRange(DateTime(2026, 9, 15), DateTime(2026, 9, 15));
      expect(single.dayCount, 1);
    });

    test('contains respects both ends', () {
      final range = DateRange(
        DateTime(2026, 9),
        DateTime(2026, 9, 30, 23, 59, 59, 999),
      );
      expect(range.contains(DateTime(2026, 9, 15)), isTrue);
      expect(range.contains(DateTime(2026, 9)), isTrue);
      expect(range.contains(DateTime(2026, 8, 31)), isFalse);
      expect(range.contains(DateTime(2026, 10)), isFalse);
    });

    test('previousPeriod is the same length, immediately before', () {
      final september = DateRange(
        DateTime(2026, 9),
        DateTime(2026, 9, 30, 23, 59, 59, 999),
      );
      final previous = september.previousPeriod;

      expect(previous.dayCount, september.dayCount);
      expect(previous.end.day, 31);
      expect(previous.end.month, 8);
      // Must not overlap, or a month-over-month comparison double-counts a day.
      expect(previous.end.isBefore(september.start), isTrue);
    });

    test('labels a whole month by its name', () {
      final range = DateRange(
        DateTime(2026, 9),
        DateTime(2026, 9, 30, 23, 59, 59, 999),
      );
      expect(range.label, 'September 2026');
    });

    test('labels a partial range with both dates', () {
      final range = DateRange(DateTime(2026, 9, 5), DateTime(2026, 9, 20));
      expect(range.label, contains('5 Sep'));
      expect(range.label, contains('20 Sep'));
    });
  });

  group('AppDateUtils.rangeFor', () {
    final reference = DateTime(2026, 9, 15);

    test('this month', () {
      final range = AppDateUtils.rangeFor(
        DateRangePreset.month,
        now: reference,
      );
      expect(range.start, DateTime(2026, 9));
      expect(range.end.day, 30);
    });

    test('three months spans the current month and the two before', () {
      final range = AppDateUtils.rangeFor(
        DateRangePreset.threeMonths,
        now: reference,
      );
      expect(range.start, DateTime(2026, 7));
      expect(range.end.month, 9);
    });

    test('a year covers January to December', () {
      final range = AppDateUtils.rangeFor(
        DateRangePreset.year,
        now: reference,
      );
      expect(range.start, DateTime(2026));
      expect(range.end.month, 12);
      expect(range.end.day, 31);
    });
  });

  group('AppDateUtils.advance', () {
    test('adds fixed intervals', () {
      final from = DateTime(2026, 9, 15);
      expect(
        AppDateUtils.advance(from, RecurrenceFrequency.daily),
        DateTime(2026, 9, 16),
      );
      expect(
        AppDateUtils.advance(from, RecurrenceFrequency.weekly),
        DateTime(2026, 9, 22),
      );
      expect(
        AppDateUtils.advance(from, RecurrenceFrequency.biweekly),
        DateTime(2026, 9, 29),
      );
    });

    test('adds months, years and quarters', () {
      final from = DateTime(2026, 9, 15);
      expect(
        AppDateUtils.advance(from, RecurrenceFrequency.monthly),
        DateTime(2026, 10, 15),
      );
      expect(
        AppDateUtils.advance(from, RecurrenceFrequency.quarterly),
        DateTime(2026, 12, 15),
      );
      expect(
        AppDateUtils.advance(from, RecurrenceFrequency.yearly),
        DateTime(2027, 9, 15),
      );
    });

    test('clamps the day instead of rolling into the next month', () {
      // A schedule set for the 31st must land on the 30th in a 30-day month,
      // not on the 1st of the month after.
      expect(
        AppDateUtils.advance(DateTime(2026, 1, 31), RecurrenceFrequency.monthly),
        DateTime(2026, 2, 28),
      );
      expect(
        AppDateUtils.advance(DateTime(2026, 3, 31), RecurrenceFrequency.monthly),
        DateTime(2026, 4, 30),
      );
      expect(
        AppDateUtils.advance(DateTime(2028, 1, 31), RecurrenceFrequency.monthly),
        DateTime(2028, 2, 29),
      );
    });

    test('keeps the day where the target month is long enough', () {
      expect(
        AppDateUtils.advance(DateTime(2026, 1, 15), RecurrenceFrequency.monthly),
        DateTime(2026, 2, 15),
      );
    });

    test('a custom interval of at least one day', () {
      expect(
        AppDateUtils.advance(
          DateTime(2026, 9, 15),
          RecurrenceFrequency.custom,
          customDays: 10,
        ),
        DateTime(2026, 9, 25),
      );
      // A zero or negative interval would loop forever, so it is floored at one.
      expect(
        AppDateUtils.advance(
          DateTime(2026, 9, 15),
          RecurrenceFrequency.custom,
          customDays: 0,
        ),
        DateTime(2026, 9, 16),
      );
    });
  });

  group('AppDateUtils.nextOccurrenceAfter', () {
    test('rolls a missed schedule forward past now', () {
      // A monthly schedule last due in January, evaluated in September, should
      // be due in September or later — not fire eight times for the past.
      final next = AppDateUtils.nextOccurrenceAfter(
        DateTime(2026, 1, 10),
        RecurrenceFrequency.monthly,
        now: DateTime(2026, 9, 15),
      );
      expect(next.isAfter(DateTime(2026, 9, 15)), isTrue);
      expect(next, DateTime(2026, 10, 10));
    });

    test('leaves a future date alone', () {
      final future = DateTime(2026, 12);
      expect(
        AppDateUtils.nextOccurrenceAfter(
          future,
          RecurrenceFrequency.monthly,
          now: DateTime(2026, 9, 15),
        ),
        future,
      );
    });

    test('terminates even for a very stale daily schedule', () {
      // The guard must stop the loop rather than hanging the app.
      final next = AppDateUtils.nextOccurrenceAfter(
        DateTime(2000),
        RecurrenceFrequency.daily,
        now: DateTime(2026, 9, 15),
      );
      expect(next, isNotNull);
    });
  });

  group('AppDateUtils.occurrencesPerMonth', () {
    test('normalises billing periods to a monthly figure', () {
      expect(
        AppDateUtils.occurrencesPerMonth(RecurrenceFrequency.monthly),
        1,
      );
      expect(
        AppDateUtils.occurrencesPerMonth(RecurrenceFrequency.yearly),
        closeTo(1 / 12, 0.0001),
      );
      expect(
        AppDateUtils.occurrencesPerMonth(RecurrenceFrequency.weekly),
        closeTo(4.348, 0.01),
      );
      expect(
        AppDateUtils.occurrencesPerMonth(RecurrenceFrequency.quarterly),
        closeTo(1 / 3, 0.0001),
      );
    });

    test('a custom interval cannot divide by zero', () {
      expect(
        AppDateUtils.occurrencesPerMonth(
          RecurrenceFrequency.custom,
          customDays: 0,
        ),
        1,
      );
    });
  });

  group('DateDisplay', () {
    test('relative names today and yesterday', () {
      expect(DateDisplay.relative(DateTime.now()), 'Today');
      expect(
        DateDisplay.relative(DateTime.now().subtract(const Duration(days: 1))),
        'Yesterday',
      );
    });

    test('section headers are upper case', () {
      expect(DateDisplay.sectionHeader(DateTime.now()), 'TODAY');
      expect(
        DateDisplay.sectionHeader(
          DateTime.now().subtract(const Duration(days: 1)),
        ),
        'YESTERDAY',
      );
    });

    test('due descriptions read naturally for each case', () {
      final today = DateTime.now();
      expect(DateDisplay.dueDescription(today), 'Due today');
      expect(
        DateDisplay.dueDescription(today.add(const Duration(days: 1))),
        'Due tomorrow',
      );
      expect(
        DateDisplay.dueDescription(today.subtract(const Duration(days: 1))),
        'Overdue by 1 day',
      );
      expect(
        DateDisplay.dueDescription(today.subtract(const Duration(days: 5))),
        'Overdue by 5 days',
      );
      expect(
        DateDisplay.dueDescription(today.add(const Duration(days: 4))),
        'Due in 4 days',
      );
    });

    test('iso format is sortable', () {
      expect(DateDisplay.iso(DateTime(2026, 9, 5)), '2026-09-05');
    });

    test('greeting changes through the day', () {
      expect(DateDisplay.greeting(DateTime(2026, 9, 15, 8)), 'Good morning');
      expect(DateDisplay.greeting(DateTime(2026, 9, 15, 14)), 'Good afternoon');
      expect(DateDisplay.greeting(DateTime(2026, 9, 15, 20)), 'Good evening');
    });
  });
}
