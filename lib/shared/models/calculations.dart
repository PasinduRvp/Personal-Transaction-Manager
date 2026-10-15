import 'package:collection/collection.dart';

import '../../core/utils/app_date_utils.dart';
import '../../core/utils/money.dart';
import 'account.dart';
import 'bill.dart';
import 'subscription.dart';
import 'transaction.dart';

/// Pure financial calculations over collections of models.
///
/// These used to be static methods on the repositories, which was the wrong
/// home: none of them touches a database, and having them there meant a unit
/// test of "do these balances add up" had to import the data layer — and so
/// broke when the backend changed, despite the arithmetic being identical.
///
/// Nothing here does I/O. Everything is deterministic and unit-tested.

/// Totals across accounts.
class AccountTotals {
  const AccountTotals._();

  /// Combined balance of the active accounts held in [currency].
  ///
  /// Accounts in another currency are skipped and counted rather than converted.
  /// A total produced at an invented exchange rate would be confidently wrong,
  /// which is worse than one that is openly incomplete — the UI reports the
  /// excluded count beneath the figure.
  static ({Money total, int excludedCount}) balance(
    List<Account> accounts,
    String currency,
  ) {
    var total = Money.zero(currency);
    var excluded = 0;

    for (final account in accounts) {
      if (!account.countsTowardNetBalance) continue;
      if (account.currency != currency) {
        excluded++;
        continue;
      }
      total += account.currentBalance;
    }

    return (total: total, excludedCount: excluded);
  }

  /// Combined balance of one account type, for the grouped accounts list.
  static Money byType(List<Account> accounts, String currency) {
    var total = Money.zero(currency);
    for (final account in accounts) {
      if (account.currency == currency) total += account.currentBalance;
    }
    return total;
  }
}

/// Grouping and totals over bills.
class BillTotals {
  const BillTotals._();

  /// Bills grouped into the buckets the Bills screen renders.
  ///
  /// Ordered by urgency rather than by enum declaration order, because that is
  /// the order someone opening this screen cares about.
  static Map<BillBucket, List<Bill>> groupByBucket(List<Bill> bills) {
    final grouped = groupBy<Bill, BillBucket>(bills, (b) => b.bucket);

    const order = [
      BillBucket.overdue,
      BillBucket.dueToday,
      BillBucket.dueTomorrow,
      BillBucket.dueThisWeek,
      BillBucket.upcoming,
      BillBucket.paid,
      BillBucket.cancelled,
    ];

    return {
      for (final bucket in order)
        if (grouped[bucket]?.isNotEmpty ?? false) bucket: grouped[bucket]!,
    };
  }

  /// Total still owed across unpaid and overdue bills in [currency].
  static Money outstanding(List<Bill> bills, String currency) {
    var total = Money.zero(currency);
    for (final bill in bills) {
      if (bill.isPaid || bill.isCancelled) continue;
      if (bill.amount.currency != currency) continue;
      total += bill.amount;
    }
    return total;
  }
}

/// Subscription cost, normalised across billing periods.
class SubscriptionTotals {
  const SubscriptionTotals._();

  /// Combined monthly cost of the active subscriptions.
  ///
  /// Yearly and weekly plans are normalised to a monthly figure so they can be
  /// added together. The number a user wants is "what do subscriptions cost me a
  /// month", which a mixed list cannot answer without this.
  static Money monthly(List<Subscription> subscriptions, String currency) {
    var total = Money.zero(currency);
    for (final subscription in subscriptions) {
      if (!subscription.isActive || subscription.isArchived) continue;
      if (subscription.amount.currency != currency) continue;
      total += subscription.monthlyCost;
    }
    return total;
  }

  static Money yearly(List<Subscription> subscriptions, String currency) =>
      monthly(subscriptions, currency) * 12;

  /// Active subscriptions renewing within [days], soonest first.
  static List<Subscription> renewingSoon(
    List<Subscription> subscriptions, {
    int days = 14,
  }) {
    final soon = subscriptions
        .where((s) =>
            s.isActive &&
            !s.isArchived &&
            s.daysUntilRenewal >= 0 &&
            s.daysUntilRenewal <= days)
        .toList()
      ..sort((a, b) => a.daysUntilRenewal.compareTo(b.daysUntilRenewal));
    return soon;
  }
}

/// Grouping over transactions.
class TransactionGrouping {
  const TransactionGrouping._();

  /// Groups a flat list into day sections for the history list, newest first.
  static List<TransactionDayGroup> byDay(List<Transaction> transactions) {
    final grouped = groupBy<Transaction, DateTime>(
      transactions,
      (t) => AppDateUtils.startOfDay(t.transactionDate),
    );

    final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return days
        .map((day) => TransactionDayGroup(
              date: day,
              transactions: grouped[day]!,
            ))
        .toList(growable: false);
  }
}
