import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/money.dart';
import '../models/analytics.dart';
import '../models/calculations.dart';
import 'account_providers.dart';
import 'auth_providers.dart';
import 'notification_providers.dart';
import 'profile_providers.dart';
import 'repository_providers.dart';

/// Everything the dashboard shows, assembled in one provider.
///
/// The individual reads are issued concurrently and the screen renders once.
/// Six independent providers would each flip to loading on their own schedule,
/// which reads as the dashboard flickering into place a piece at a time.
class DashboardController extends AsyncNotifier<DashboardData> {
  @override
  Future<DashboardData> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) throw StateError('No signed-in user');

    // Watched, not read: a currency change or a new account must refresh the
    // dashboard rather than leave stale figures on screen.
    final currency = ref.watch(currencyProvider);
    final accounts = ref.watch(accountsControllerProvider).valueOrNull;

    final analytics = ref.read(analyticsRepositoryProvider);
    final transactions = ref.read(transactionRepositoryProvider);
    final budgets = ref.read(budgetRepositoryProvider);
    final bills = ref.read(billRepositoryProvider);
    final savings = ref.read(savingsRepositoryProvider);
    final ocr = ref.read(ocrRepositoryProvider);
    final notifications = ref.read(notificationRepositoryProvider);
    final accountsRepo = ref.read(accountRepositoryProvider);

    final thisMonth = AppDateUtils.thisMonth();
    final trendRange = DateRange(
      AppDateUtils.startOfMonth(
        DateTime(DateTime.now().year, DateTime.now().month - 5),
      ),
      AppDateUtils.endOfMonth(DateTime.now()),
    );

    // Record `.wait` rather than `Future.wait([...])`: the results stay typed,
    // so a reordering mistake is a compile error instead of a runtime cast.
    // Split across two waits because the record form tops out at nine fields.
    final (accountList, monthSummary, previousSummary, recent, progress) =
        await (
      accounts != null
          ? Future.value(accounts)
          : accountsRepo.fetchAll(),
      analytics.fetchCashflow(range: thisMonth, currency: currency),
      analytics.fetchCashflow(
        range: thisMonth.previousPeriod,
        currency: currency,
      ),
      transactions.fetchRecent(limit: 8),
      budgets.fetchProgress(fallbackCurrency: currency),
    ).wait;

    final (upcomingBills, goals, trend, breakdown, pendingOcr, unread) =
        await (
      bills.fetchUpcoming(limit: 4),
      savings.fetchAll(),
      analytics.fetchTimeSeries(
        range: trendRange,
        currency: currency,
        daily: false,
      ),
      analytics.fetchCategoryBreakdown(range: thisMonth, currency: currency),
      ocr.pendingCandidateCount(),
      notifications.unreadCount(),
    ).wait;

    final balance = AccountTotals.balance(accountList, currency);

    return DashboardData(
      currency: currency,
      totalBalance: balance.total,
      monthSummary: monthSummary,
      previousMonthSummary: previousSummary,
      accounts: accountList,
      recentTransactions: recent,
      budgets: progress,
      upcomingBills: upcomingBills,
      savingsGoals: goals,
      spendingTrend: trend,
      categoryBreakdown: breakdown,
      pendingOcrCount: pendingOcr,
      unreadNotificationCount: unread,
      generatedAt: DateTime.now(),
    );
  }

  Future<void> refresh() async {
    ref.invalidate(accountsControllerProvider);
    ref.invalidate(unreadNotificationCountProvider);
    state = const AsyncValue<DashboardData>.loading();
    ref.invalidateSelf();
    await future;
  }
}

final dashboardControllerProvider =
    AsyncNotifierProvider<DashboardController, DashboardData>(
  DashboardController.new,
);

/// The six-month spending trend, already shaped for the chart.
final spendingTrendProvider = Provider<TimeSeries>((ref) {
  final data = ref.watch(dashboardControllerProvider).valueOrNull;
  return data?.spendingTrend ??
      TimeSeries(points: const [], currency: ref.watch(currencyProvider));
});

/// Top spending categories for the dashboard donut, with the tail folded into
/// a single "Other" slice so the chart stays readable.
final dashboardCategorySlicesProvider =
    Provider.family<List<CategoryBreakdownItem>, bool>((ref, isDark) {
  final breakdown = ref.watch(dashboardControllerProvider).valueOrNull
      ?.categoryBreakdown;
  if (breakdown == null || breakdown.isEmpty) return const [];
  return breakdown.topWithOther(
    5,
    isDark ? AppColors.textTertiaryDark : AppColors.textTertiary,
  );
});

/// This month's savings figure, exposed on its own for the summary tile.
final monthSavingsProvider = Provider<Money>((ref) {
  final data = ref.watch(dashboardControllerProvider).valueOrNull;
  return data?.monthSummary.savings ?? Money.zero(ref.watch(currencyProvider));
});
