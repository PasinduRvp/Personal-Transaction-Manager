import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/enums.dart';
import '../../core/utils/app_date_utils.dart';
import '../models/analytics.dart';
import '../models/transaction.dart';
import '../models/transaction_query.dart';
import 'account_providers.dart';
import 'auth_providers.dart';
import 'profile_providers.dart';
import 'repository_providers.dart';

/// The period and account filter the Analytics screen is showing.
class AnalyticsFilter {
  const AnalyticsFilter({
    this.preset = DateRangePreset.month,
    this.customRange,
    this.accountIds = const {},
  });

  final DateRangePreset preset;

  /// Only used when [preset] is custom.
  final DateRange? customRange;
  final Set<String> accountIds;

  DateRange get range => preset == DateRangePreset.custom && customRange != null
      ? customRange!.normalised()
      : AppDateUtils.rangeFor(preset);

  AnalyticsFilter copyWith({
    DateRangePreset? preset,
    DateRange? customRange,
    Set<String>? accountIds,
  }) =>
      AnalyticsFilter(
        preset: preset ?? this.preset,
        customRange: customRange ?? this.customRange,
        accountIds: accountIds ?? this.accountIds,
      );

  @override
  bool operator ==(Object other) =>
      other is AnalyticsFilter &&
      other.preset == preset &&
      other.customRange == customRange &&
      other.accountIds.length == accountIds.length &&
      other.accountIds.containsAll(accountIds);

  @override
  int get hashCode => Object.hash(
        preset,
        customRange,
        Object.hashAllUnordered(accountIds),
      );
}

class AnalyticsFilterController extends Notifier<AnalyticsFilter> {
  @override
  AnalyticsFilter build() => const AnalyticsFilter();

  void setPreset(DateRangePreset preset) =>
      state = state.copyWith(preset: preset);

  void setCustomRange(DateRange range) => state = state.copyWith(
        preset: DateRangePreset.custom,
        customRange: range,
      );

  void toggleAccount(String id) {
    final next = Set<String>.from(state.accountIds);
    next.contains(id) ? next.remove(id) : next.add(id);
    state = state.copyWith(accountIds: next);
  }

  void clearAccounts() => state = state.copyWith(accountIds: const {});
}

final analyticsFilterProvider =
    NotifierProvider<AnalyticsFilterController, AnalyticsFilter>(
  AnalyticsFilterController.new,
);

/// The full analytics payload for the current filter.
final analyticsDataProvider = FutureProvider<AnalyticsData>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) throw StateError('No signed-in user');

  final filter = ref.watch(analyticsFilterProvider);
  final currency = ref.watch(currencyProvider);
  final accounts = ref.watch(accountsControllerProvider).valueOrNull ?? const [];

  return ref.watch(analyticsRepositoryProvider).fetchAnalytics(
        range: filter.range,
        currency: currency,
        accounts: accounts,
        accountIds: filter.accountIds,
      );
});

/// Transactions behind a chart element, so tapping a category slice or a month
/// bar can show what produced it.
final drillDownProvider =
    FutureProvider.family<List<Transaction>, DrillDown>((ref, drill) {
  final filter = ref.watch(analyticsFilterProvider);

  final query = TransactionQuery(
    types: {drill.type},
    categoryIds: drill.categoryId == null ? const {} : {drill.categoryId!},
    accountIds: filter.accountIds,
    dateRange: drill.range ?? filter.range,
    sort: TransactionSort.amountHigh,
    statuses: const {TransactionStatus.confirmed},
  );

  return ref.watch(transactionRepositoryProvider).fetchRange(
        range: query.dateRange!,
        query: query,
        limit: 200,
      );
});

/// What a chart tap is asking about.
class DrillDown {
  const DrillDown({
    required this.type,
    this.categoryId,
    this.merchant,
    this.range,
    this.label,
  });

  final TransactionType type;
  final String? categoryId;
  final String? merchant;

  /// Overrides the screen's range, for a tap on one month in a trend chart.
  final DateRange? range;

  /// Title for the drill-down sheet.
  final String? label;

  @override
  bool operator ==(Object other) =>
      other is DrillDown &&
      other.type == type &&
      other.categoryId == categoryId &&
      other.merchant == merchant &&
      other.range == range;

  @override
  int get hashCode => Object.hash(type, categoryId, merchant, range);
}

/// The report payload for the Reports screen, which uses the same aggregates as
/// Analytics plus the transaction list needed for CSV and PDF export.
final reportDataProvider =
    FutureProvider.family<ReportData, DateRange>((ref, range) async {
  final currency = ref.watch(currencyProvider);
  final accounts = ref.watch(accountsControllerProvider).valueOrNull ?? const [];
  final analytics = ref.watch(analyticsRepositoryProvider);
  final transactions = ref.watch(transactionRepositoryProvider);
  final budgets = ref.watch(budgetRepositoryProvider);
  final profile = ref.watch(profileControllerProvider).valueOrNull;

  final (summary, expenseBreakdown, trend, rows, budgetProgress) = await (
    analytics.fetchCashflow(range: range, currency: currency),
    analytics.fetchCategoryBreakdown(range: range, currency: currency),
    analytics.fetchTimeSeries(range: range, currency: currency, daily: false),
    transactions.fetchRange(range: range),
    budgets.fetchProgress(reference: range.end, fallbackCurrency: currency),
  ).wait;

  final expenses = rows
      .where((t) => t.countsAsExpense)
      .toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));

  return ReportData(
    range: range,
    currency: currency,
    userName: profile?.fullName ?? profile?.displayName ?? 'Finora user',
    summary: summary,
    categoryBreakdown: expenseBreakdown,
    trend: trend,
    transactions: rows,
    largestExpenses: expenses.take(10).toList(growable: false),
    budgets: budgetProgress,
    accounts: accounts,
    generatedAt: DateTime.now(),
  );
});
