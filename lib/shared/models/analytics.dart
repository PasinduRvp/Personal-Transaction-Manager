import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../core/constants/enums.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/money.dart';
import 'account.dart';
import 'bill.dart';
import 'budget.dart';
import 'savings_goal.dart';
import 'transaction.dart';

/// Income, expense and savings for one period.
///
/// Transfers are excluded by construction: the aggregation that produces this
/// only reads confirmed income and expense rows, so moving money between the
/// user's own accounts never inflates either figure.
class CashflowSummary extends Equatable {
  const CashflowSummary({
    required this.range,
    required this.income,
    required this.expenses,
  });

  CashflowSummary.empty(this.range, String currency)
      : income = Money.zero(currency),
        expenses = Money.zero(currency);

  final DateRange range;
  final Money income;
  final Money expenses;

  String get currency => income.currency;

  /// Savings = income − expenses. May be negative when the user overspent.
  Money get savings => income - expenses;

  /// Savings as a percentage of income. Zero when there was no income, rather
  /// than infinity.
  double get savingsRate {
    if (income.isZero) return 0;
    return (savings.minorUnits / income.minorUnits) * 100;
  }

  bool get isOverspending => savings.isNegative;

  /// Average daily spend over the period.
  Money get averageDailySpend {
    final days = range.dayCount;
    if (days <= 0) return Money.zero(currency);
    return expenses * (1 / days);
  }

  /// Percentage change against a previous period. Null when the previous
  /// period had no activity to compare against.
  static double? changePercent(Money current, Money previous) {
    if (previous.isZero) return null;
    return ((current.minorUnits - previous.minorUnits) /
            previous.minorUnits.abs()) *
        100;
  }

  @override
  List<Object?> get props => [range, income, expenses];
}

/// One slice of the category breakdown.
class CategoryBreakdownItem extends Equatable {
  const CategoryBreakdownItem({
    required this.categoryId,
    required this.categoryName,
    required this.total,
    required this.transactionCount,
    required this.color,
    this.icon,
  });

  final String? categoryId;
  final String categoryName;
  final Money total;
  final int transactionCount;
  final Color color;
  final IconData? icon;

  /// Share of the grand total, supplied by [CategoryBreakdown].
  double shareOf(Money grandTotal) => total.percentOf(grandTotal);

  @override
  List<Object?> get props =>
      [categoryId, categoryName, total, transactionCount];
}

class CategoryBreakdown extends Equatable {
  const CategoryBreakdown({
    required this.items,
    required this.total,
    required this.range,
  });

  final List<CategoryBreakdownItem> items;
  final Money total;
  final DateRange range;

  bool get isEmpty => items.isEmpty;

  CategoryBreakdownItem? get largest => items.isEmpty ? null : items.first;

  /// The top [count] categories, with everything else folded into one "Other"
  /// slice so the chart stays readable.
  List<CategoryBreakdownItem> topWithOther(int count, Color otherColor) {
    if (items.length <= count) return items;
    final top = items.take(count).toList();
    final rest = items.skip(count);
    final restTotal = rest.map((e) => e.total).reduce((a, b) => a + b);
    return [
      ...top,
      CategoryBreakdownItem(
        categoryId: null,
        categoryName: 'Other',
        total: restTotal,
        transactionCount: rest.fold(0, (sum, e) => sum + e.transactionCount),
        color: otherColor,
      ),
    ];
  }

  @override
  List<Object?> get props => [items, total, range];
}

/// One point on a time series (monthly spending, cash flow, savings trend).
class TimeSeriesPoint extends Equatable {
  const TimeSeriesPoint({
    required this.periodStart,
    required this.label,
    required this.income,
    required this.expenses,
  });

  final DateTime periodStart;

  /// Short axis label, e.g. `Sep`.
  final String label;
  final Money income;
  final Money expenses;

  Money get net => income - expenses;

  @override
  List<Object?> get props => [periodStart, label, income, expenses];
}

class TimeSeries extends Equatable {
  const TimeSeries({required this.points, required this.currency});

  final List<TimeSeriesPoint> points;
  final String currency;

  bool get isEmpty => points.isEmpty;

  Money get maxValue {
    if (points.isEmpty) return Money.zero(currency);
    var max = Money.zero(currency);
    for (final p in points) {
      if (p.income > max) max = p.income;
      if (p.expenses > max) max = p.expenses;
    }
    return max;
  }

  /// Running balance across the series, for the savings-trend chart.
  List<Money> get cumulativeNet {
    var running = Money.zero(currency);
    return points.map((p) {
      running = running + p.net;
      return running;
    }).toList();
  }

  @override
  List<Object?> get props => [points, currency];
}

/// A merchant with its total spend, for the "top merchants" list.
class MerchantTotal extends Equatable {
  const MerchantTotal({
    required this.merchant,
    required this.total,
    required this.transactionCount,
    this.lastTransactionDate,
  });

  final String merchant;
  final Money total;
  final int transactionCount;
  final DateTime? lastTransactionDate;

  Money get average => transactionCount == 0
      ? Money.zero(total.currency)
      : total * (1 / transactionCount);

  @override
  List<Object?> get props => [merchant, total, transactionCount];
}

/// Spend grouped by payment method.
class PaymentMethodTotal extends Equatable {
  const PaymentMethodTotal({
    required this.method,
    required this.total,
    required this.transactionCount,
  });

  final PaymentMethod? method;
  final Money total;
  final int transactionCount;

  String get label => method?.label ?? 'Not specified';

  @override
  List<Object?> get props => [method, total, transactionCount];
}

/// Everything the dashboard needs, fetched as one unit so the screen renders in
/// a single frame rather than stuttering through six independent loads.
class DashboardData extends Equatable {
  const DashboardData({
    required this.currency,
    required this.totalBalance,
    required this.monthSummary,
    required this.previousMonthSummary,
    required this.accounts,
    required this.recentTransactions,
    required this.budgets,
    required this.upcomingBills,
    required this.savingsGoals,
    required this.spendingTrend,
    required this.categoryBreakdown,
    required this.pendingOcrCount,
    required this.unreadNotificationCount,
    required this.generatedAt,
  });

  final String currency;

  /// Sum of every active, non-archived account's current balance.
  final Money totalBalance;
  final CashflowSummary monthSummary;
  final CashflowSummary previousMonthSummary;
  final List<Account> accounts;
  final List<Transaction> recentTransactions;
  final List<BudgetProgress> budgets;
  final List<Bill> upcomingBills;
  final List<SavingsGoal> savingsGoals;
  final TimeSeries spendingTrend;
  final CategoryBreakdown categoryBreakdown;

  /// Candidates awaiting review, surfaced as a prompt on the dashboard.
  final int pendingOcrCount;
  final int unreadNotificationCount;

  /// When this snapshot was built — shown as "Updated 2 minutes ago" when the
  /// data came from the offline cache.
  final DateTime generatedAt;

  double? get incomeChangePercent => CashflowSummary.changePercent(
      monthSummary.income, previousMonthSummary.income);

  double? get expenseChangePercent => CashflowSummary.changePercent(
      monthSummary.expenses, previousMonthSummary.expenses);

  bool get hasAnyData =>
      accounts.isNotEmpty || recentTransactions.isNotEmpty;

  List<BudgetProgress> get budgetsNeedingAttention => budgets
      .where((b) => b.isAtThreshold || b.isExceeded)
      .toList(growable: false);

  @override
  List<Object?> get props => [
        currency,
        totalBalance,
        monthSummary,
        previousMonthSummary,
        accounts,
        recentTransactions,
        budgets,
        upcomingBills,
        savingsGoals,
        spendingTrend,
        categoryBreakdown,
        pendingOcrCount,
        unreadNotificationCount,
      ];
}

/// Everything a monthly report contains.
///
/// Carries the full transaction list as well as the aggregates, because CSV
/// export needs the rows and the PDF needs the totals, and computing them from
/// two different sources would let the report disagree with itself.
class ReportData extends Equatable {
  const ReportData({
    required this.range,
    required this.currency,
    required this.userName,
    required this.summary,
    required this.categoryBreakdown,
    required this.trend,
    required this.transactions,
    required this.largestExpenses,
    required this.budgets,
    required this.accounts,
    required this.generatedAt,
  });

  final DateRange range;
  final String currency;
  final String userName;
  final CashflowSummary summary;
  final CategoryBreakdown categoryBreakdown;
  final TimeSeries trend;

  /// Every transaction in the period, including transfers, so the CSV is a
  /// complete record. Totals still exclude transfers.
  final List<Transaction> transactions;
  final List<Transaction> largestExpenses;
  final List<BudgetProgress> budgets;
  final List<Account> accounts;
  final DateTime generatedAt;

  bool get isEmpty => transactions.isEmpty;

  int get transactionCount => transactions.length;

  List<CategoryBreakdownItem> get topCategories =>
      categoryBreakdown.items.take(8).toList(growable: false);

  @override
  List<Object?> get props => [
        range,
        currency,
        userName,
        summary,
        categoryBreakdown,
        transactions,
        budgets,
        accounts,
      ];
}

/// The full analytics payload for the Analytics screen.
class AnalyticsData extends Equatable {
  const AnalyticsData({
    required this.range,
    required this.currency,
    required this.summary,
    required this.previousSummary,
    required this.expenseBreakdown,
    required this.incomeBreakdown,
    required this.monthlyTrend,
    required this.topMerchants,
    required this.paymentMethods,
    required this.accountBalances,
    required this.transactionCount,
    required this.largestExpense,
  });

  final DateRange range;
  final String currency;
  final CashflowSummary summary;
  final CashflowSummary previousSummary;
  final CategoryBreakdown expenseBreakdown;
  final CategoryBreakdown incomeBreakdown;
  final TimeSeries monthlyTrend;
  final List<MerchantTotal> topMerchants;
  final List<PaymentMethodTotal> paymentMethods;
  final List<Account> accountBalances;
  final int transactionCount;
  final Transaction? largestExpense;

  bool get isEmpty => transactionCount == 0;

  @override
  List<Object?> get props => [
        range,
        currency,
        summary,
        previousSummary,
        expenseBreakdown,
        incomeBreakdown,
        monthlyTrend,
        topMerchants,
        paymentMethods,
        accountBalances,
        transactionCount,
      ];
}
