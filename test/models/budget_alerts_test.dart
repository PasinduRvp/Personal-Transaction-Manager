import 'package:finora/core/constants/enums.dart';
import 'package:finora/core/utils/app_date_utils.dart';
import 'package:finora/core/utils/money.dart';
import 'package:finora/shared/models/budget.dart';
import 'package:flutter_test/flutter_test.dart';

/// The budget alert rules: which thresholds a figure has crossed, and which of
/// those have not been announced yet.
///
/// These decide whether a user is told about their own overspending, so the
/// boundaries are asserted exactly — 74.9% is not 75%, and exactly 100% is
/// spent rather than exceeded.
Budget budget({
  int limitMinor = 100000,
  DateTime? alertedPeriodStart,
  List<String> alertedLevels = const [],
  bool isArchived = false,
}) {
  final now = DateTime(2026, 11, 1);
  return Budget(
    id: 'b1',
    userId: 'u1',
    amount: Money.fromMinorUnits(limitMinor),
    period: BudgetPeriod.monthly,
    startDate: now,
    isArchived: isArchived,
    alertedPeriodStart: alertedPeriodStart,
    alertedLevels: alertedLevels,
    createdAt: now,
    updatedAt: now,
  );
}

BudgetProgress progress({
  required int spentMinor,
  int limitMinor = 100000,
  DateTime? alertedPeriodStart,
  List<String> alertedLevels = const [],
}) {
  final reference = DateTime(2026, 11, 15);
  return BudgetProgress(
    budget: budget(
      limitMinor: limitMinor,
      alertedPeriodStart: alertedPeriodStart,
      alertedLevels: alertedLevels,
    ),
    spent: Money.fromMinorUnits(spentMinor),
    range: DateRange(
      AppDateUtils.startOfMonth(reference),
      AppDateUtils.endOfMonth(reference),
    ),
  );
}

/// The start of the period the fixtures above sit in.
final periodStart = AppDateUtils.startOfMonth(DateTime(2026, 11, 15));

void main() {
  group('BudgetAlertLevel thresholds', () {
    test('each level starts at its own percentage', () {
      expect(BudgetAlertLevel.threeQuarters.reachedBy(74.9), isFalse);
      expect(BudgetAlertLevel.threeQuarters.reachedBy(75), isTrue);

      expect(BudgetAlertLevel.ninety.reachedBy(89.9), isFalse);
      expect(BudgetAlertLevel.ninety.reachedBy(90), isTrue);

      expect(BudgetAlertLevel.spent.reachedBy(99.9), isFalse);
      expect(BudgetAlertLevel.spent.reachedBy(100), isTrue);
    });

    test('exactly at the limit is spent, not overspent', () {
      // A budget used to the last rupee is not an overspend, and saying so
      // over a rounding error would be a false alarm about the user's money.
      expect(BudgetAlertLevel.overspent.reachedBy(100), isFalse);
      expect(BudgetAlertLevel.overspent.reachedBy(100.01), isTrue);
    });

    test('the two upper levels are exceeded, the lower two are warnings', () {
      expect(BudgetAlertLevel.threeQuarters.isExceeded, isFalse);
      expect(BudgetAlertLevel.ninety.isExceeded, isFalse);
      expect(BudgetAlertLevel.spent.isExceeded, isTrue);
      expect(BudgetAlertLevel.overspent.isExceeded, isTrue);
    });

    test('warnings and exceedances map to the settings flags that govern them',
        () {
      expect(
        BudgetAlertLevel.threeQuarters.kind,
        NotificationKind.budgetWarning,
      );
      expect(BudgetAlertLevel.ninety.kind, NotificationKind.budgetWarning);
      expect(BudgetAlertLevel.spent.kind, NotificationKind.budgetExceeded);
      expect(
        BudgetAlertLevel.overspent.kind,
        NotificationKind.budgetExceeded,
      );
    });
  });

  group('Levels reached', () {
    test('nothing is reached below the first threshold', () {
      expect(progress(spentMinor: 74000).reachedLevels, isEmpty);
    });

    test('lower levels remain reached once a higher one is', () {
      // One large transaction can push a budget from 70% to 105%. The user
      // should get every level it passed, not only the highest.
      final levels = progress(spentMinor: 105000).reachedLevels;

      expect(levels, [
        BudgetAlertLevel.threeQuarters,
        BudgetAlertLevel.ninety,
        BudgetAlertLevel.spent,
        BudgetAlertLevel.overspent,
      ]);
    });

    test('at ninety per cent the two warning levels are reached', () {
      expect(progress(spentMinor: 90000).reachedLevels, [
        BudgetAlertLevel.threeQuarters,
        BudgetAlertLevel.ninety,
      ]);
    });
  });

  group('Pending alerts', () {
    test('a level already raised this period is not raised again', () {
      final item = progress(
        spentMinor: 80000,
        alertedPeriodStart: periodStart,
        alertedLevels: const ['75'],
      );

      expect(item.reachedLevels, [BudgetAlertLevel.threeQuarters]);
      expect(item.pendingAlerts, isEmpty);
    });

    test('a newly crossed level is pending while an old one is not', () {
      final item = progress(
        spentMinor: 95000,
        alertedPeriodStart: periodStart,
        alertedLevels: const ['75'],
      );

      expect(item.pendingAlerts, [BudgetAlertLevel.ninety]);
    });

    test('a new period starts clean even with levels recorded', () {
      // The stamp belongs to October; the figures are November's, so nothing
      // has been announced yet for this period.
      final item = progress(
        spentMinor: 95000,
        alertedPeriodStart: DateTime(2026, 10, 1),
        alertedLevels: const ['75', '90', '100'],
      );

      expect(item.hasAlertStateForPeriod, isFalse);
      expect(item.pendingAlerts, [
        BudgetAlertLevel.threeQuarters,
        BudgetAlertLevel.ninety,
      ]);
    });

    test('a budget never alerted on has everything pending', () {
      final item = progress(spentMinor: 100000);

      expect(item.hasAlertStateForPeriod, isFalse);
      expect(item.pendingAlerts, [
        BudgetAlertLevel.threeQuarters,
        BudgetAlertLevel.ninety,
        BudgetAlertLevel.spent,
      ]);
    });

    test('spending falling back does not re-arm a level already raised', () {
      // Deleting a transaction can drop a budget back under 75%. Rising past
      // it again should not repeat an alert the user has already seen.
      final item = progress(
        spentMinor: 60000,
        alertedPeriodStart: periodStart,
        alertedLevels: const ['75'],
      );

      expect(item.reachedLevels, isEmpty);
      expect(item.pendingAlerts, isEmpty);
    });
  });

  group('Overspend figures', () {
    test('the body of an overspend alert has a real amount to report', () {
      final item = progress(spentMinor: 125000);

      expect(item.overspend.minorUnits, 25000);
      expect(item.remaining.minorUnits, 0);
      expect(item.percentUsed, 125);
    });
  });

  group('Notification categories', () {
    test('every kind belongs to exactly one category', () {
      for (final kind in NotificationKind.values) {
        expect(kind.category, isA<NotificationCategory>());
      }
    });

    test('budget kinds group together, imports separately', () {
      expect(
        NotificationKind.budgetWarning.category,
        NotificationCategory.budgets,
      );
      expect(
        NotificationKind.budgetExceeded.category,
        NotificationCategory.budgets,
      );
      expect(
        NotificationKind.ocrFailed.category,
        NotificationCategory.imports,
      );
      expect(
        NotificationKind.creditCardDue.category,
        NotificationCategory.payments,
      );
    });
  });
}
