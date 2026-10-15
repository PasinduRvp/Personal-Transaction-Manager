import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../shared/models/analytics.dart';
import '../../../shared/providers/core_providers.dart';
import '../../../shared/providers/dashboard_providers.dart';
import '../../../shared/providers/notification_providers.dart';
import '../../../shared/models/transaction_query.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/providers/transaction_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/charts.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import 'dashboard_sections.dart';

/// The home screen.
///
/// Ordered by what a user opens the app to find out: how much they have, what
/// this month looks like, whether a budget is in trouble, and what they spent
/// most recently. Anything that needs attention (a failed import, an exceeded
/// budget) surfaces above the rest rather than waiting to be discovered.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardControllerProvider);
    final isOffline = ref.watch(isOfflineProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(dashboardControllerProvider.notifier).refresh(),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: dashboard.view(
              (data) => _DashboardBody(data: data, isOffline: isOffline),
              loading: const _DashboardSkeleton(),
              onRetry: () =>
                  ref.read(dashboardControllerProvider.notifier).refresh(),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.data, required this.isOffline});

  final DashboardData data;
  final bool isOffline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final obscure = ref.watch(hideAmountsProvider);

    // A brand-new account has nothing to show; walk the user into it instead of
    // rendering a page of zeros.
    if (!data.hasAnyData) {
      return const _DashboardOnboarding();
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              if (isOffline) OfflineBanner(lastUpdated: data.generatedAt),
              const _DashboardHeader(),
            ],
          ),
        ),

        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.sm,
            AppSpacing.page,
            0,
          ),
          sliver: SliverList.list(
            children: [
              BalanceCard(data: data, obscured: obscure),
              AppSpacing.gapLg,
              MonthSummaryCard(data: data, obscured: obscure),

              // Attention items, only when there is something to attend to.
              if (data.pendingOcrCount > 0) ...[
                AppSpacing.gapLg,
                PendingImportsCard(count: data.pendingOcrCount),
              ],
              if (data.budgetsNeedingAttention.isNotEmpty) ...[
                AppSpacing.gapLg,
                BudgetAlertCard(budgets: data.budgetsNeedingAttention),
              ],
            ],
          ),
        ),



        if (data.spendingTrend.points.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: SectionHeading(title: 'Income vs spending'),
          ),
          SliverPadding(
            padding: AppSpacing.pageInsets,
            sliver: SliverToBoxAdapter(
              child: AppCard(
                child: Column(
                  children: [
                    IncomeExpenseBarChart(
                      series: data.spendingTrend,
                      onBarTap: (point) => _openMonth(context, ref, point),
                    ),
                    AppSpacing.gapLg,
                    ChartLegendRow(
                      entries: [
                        (label: 'Income', color: context.palette.income),
                        (label: 'Spending', color: context.palette.expense),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],

        if (!data.categoryBreakdown.isEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeading(
              title: 'Where your money went',
              actionLabel: 'Analytics',
              onAction: () => context.go(AppRoutes.analytics),
            ),
          ),
          SliverPadding(
            padding: AppSpacing.pageInsets,
            sliver: SliverToBoxAdapter(
              child: SpendingBreakdownCard(
                breakdown: data.categoryBreakdown,
              ),
            ),
          ),
        ],

        if (data.budgets.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeading(
              title: 'Budgets',
              actionLabel: 'See all',
              onAction: () => context.go(AppRoutes.budgets),
            ),
          ),
          SliverPadding(
            padding: AppSpacing.pageInsets,
            sliver: SliverToBoxAdapter(
              child: BudgetProgressList(
                budgets: data.budgets.take(4).toList(),
                obscured: obscure,
              ),
            ),
          ),
        ],

        if (data.upcomingBills.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeading(
              title: 'Upcoming bills',
              actionLabel: 'See all',
              onAction: () => context.push(AppRoutes.bills),
            ),
          ),
          SliverPadding(
            padding: AppSpacing.pageInsets,
            sliver: SliverToBoxAdapter(
              child: UpcomingBillsCard(bills: data.upcomingBills),
            ),
          ),
        ],

        if (data.savingsGoals.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeading(
              title: 'Savings goals',
              actionLabel: 'See all',
              onAction: () => context.push(AppRoutes.savings),
            ),
          ),
          SliverPadding(
            padding: AppSpacing.pageInsets,
            sliver: SliverToBoxAdapter(
              child: SavingsGoalsPreview(
                goals: data.savingsGoals.take(3).toList(),
                obscured: obscure,
              ),
            ),
          ),
        ],

        SliverToBoxAdapter(
          child: SectionHeading(
            title: 'Recent transactions',
            actionLabel: 'See all',
            onAction: () => context.go(AppRoutes.transactions),
          ),
        ),
        SliverToBoxAdapter(
          child: RecentTransactionsList(
            transactions: data.recentTransactions,
            obscured: obscure,
          ),
        ),

        const SliverToBoxAdapter(
          child: SizedBox(height: AppSpacing.bottomNavClearance),
        ),
      ],
    );
  }

  /// Opens the transaction list already filtered to the month that was tapped.
  ///
  /// The filter is applied through its provider rather than passed as a query
  /// string, because the list lives in a shell branch that does not re-read the
  /// route — a query parameter would have looked right and done nothing.
  void _openMonth(BuildContext context, WidgetRef ref, TimeSeriesPoint point) {
    ref.read(transactionQueryProvider.notifier).apply(
          TransactionQuery(
            dateRange: DateRange(
              AppDateUtils.startOfMonth(point.periodStart),
              AppDateUtils.endOfMonth(point.periodStart),
            ),
          ),
        );
    context.go(AppRoutes.transactions);
  }
}

/// Greeting, notification bell and privacy toggle.
class _DashboardHeader extends ConsumerWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileControllerProvider).valueOrNull;
    final unread = ref.watch(unreadNotificationStreamProvider).valueOrNull ??
        ref.watch(unreadNotificationCountProvider).valueOrNull ??
        0;
    final obscure = ref.watch(hideAmountsProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: context.colors.primary.withValues(alpha: 0.12),
              borderRadius: AppRadius.mdAll,
              border: Border.all(
                color: context.colors.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Image.asset(
              'assets/images/logo.png',
              width: 32,
              height: 32,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                Icons.account_balance_wallet_rounded,
                color: context.colors.primary,
                size: 26,
              ),
            ),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${DateDisplay.greeting()}, '
                  '${profile?.displayName ?? 'there'}',
                  style: context.text.headlineSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Your financial overview',
                  style: context.text.bodyMedium,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => ref
                .read(settingsControllerProvider.notifier)
                .setHideAmounts(!obscure),
            icon: Icon(
              obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            tooltip: obscure ? 'Show amounts' : 'Hide amounts',
          ),
          _NotificationBell(unreadCount: unread),
        ],
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.unreadCount});

  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topRight,
      children: [
        IconButton(
          onPressed: () => context.push(AppRoutes.notifications),
          icon: const Icon(Icons.notifications_none_rounded),
          tooltip: 'Notifications',
        ),
        if (unreadCount > 0)
          Positioned(
            top: 8,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: BoxDecoration(
                color: context.palette.danger,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: context.colors.surface, width: 1.5),
              ),
              child: Text(
                unreadCount > 9 ? '9+' : '$unreadCount',
                textAlign: TextAlign.center,
                style: context.text.labelSmall?.copyWith(
                  color: Colors.white,
                  fontSize: 9,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Shown when the account has no accounts and no transactions yet.
class _DashboardOnboarding extends ConsumerStatefulWidget {
  const _DashboardOnboarding();

  @override
  ConsumerState<_DashboardOnboarding> createState() =>
      _DashboardOnboardingState();
}

class _DashboardOnboardingState extends ConsumerState<_DashboardOnboarding>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Animation<double> _stepAnim(double start, double end) {
    return CurvedAnimation(
      parent: _animController,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileControllerProvider).valueOrNull;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        AppSpacing.gapLg,
        // Hero Logo and Header
        FadeTransition(
          opacity: _stepAnim(0.0, 0.4),
          child: ScaleTransition(
            scale: _stepAnim(0.0, 0.5),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: context.colors.primary.withValues(alpha: 0.2),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/images/logo.png',
                  height: 64,
                  width: 64,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.account_balance_wallet_rounded,
                    size: 56,
                    color: context.colors.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
        AppSpacing.gapLg,

        FadeTransition(
          opacity: _stepAnim(0.2, 0.6),
          child: Column(
            children: [
              Text(
                'Welcome to Finora, ${profile?.displayName ?? 'there'}!',
                style: context.text.headlineSmall,
                textAlign: TextAlign.center,
              ),
              AppSpacing.gapSm,
              Text(
                'Let\'s set up your financial workspace in three quick steps.',
                style: context.text.bodyMedium?.copyWith(
                  color: context.palette.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        AppSpacing.gapXxl,

        // Step 1
        SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.2),
            end: Offset.zero,
          ).animate(_stepAnim(0.3, 0.7)),
          child: FadeTransition(
            opacity: _stepAnim(0.3, 0.7),
            child: _OnboardingStep(
              step: 1,
              icon: Icons.account_balance_outlined,
              title: 'Add an account',
              message:
                  'A bank account, cash, or e-wallet — whatever you spend from.',
              actionLabel: 'Add account',
              onAction: () => context.push(AppRoutes.accountAdd),
            ),
          ),
        ),
        AppSpacing.gapLg,

        // Step 2
        SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.2),
            end: Offset.zero,
          ).animate(_stepAnim(0.5, 0.9)),
          child: FadeTransition(
            opacity: _stepAnim(0.5, 0.9),
            child: _OnboardingStep(
              step: 2,
              icon: Icons.receipt_long_outlined,
              title: 'Record a transaction',
              message:
                  'Enter one manually or scan a receipt with built-in OCR.',
              actionLabel: 'Add transaction',
              onAction: () => context.push(AppRoutes.transactionAdd),
            ),
          ),
        ),
        AppSpacing.gapLg,

        // Step 3
        SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.2),
            end: Offset.zero,
          ).animate(_stepAnim(0.7, 1.0)),
          child: FadeTransition(
            opacity: _stepAnim(0.7, 1.0),
            child: _OnboardingStep(
              step: 3,
              icon: Icons.pie_chart_outline_rounded,
              title: 'Set a budget',
              message:
                  'Pick a category and monthly limit to keep your spending on track.',
              actionLabel: 'Create budget',
              onAction: () => context.push(AppRoutes.budgetAdd),
            ),
          ),
        ),
        AppSpacing.gapXxl,
      ],
    );
  }
}

class _OnboardingStep extends StatelessWidget {
  const _OnboardingStep({
    required this.step,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final int step;
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, color: context.colors.primary, size: 48),
          AppSpacing.hGapLg,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'STEP $step OF 3',
                  style: context.text.labelSmall?.copyWith(
                    color: context.colors.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(title, style: context.text.titleMedium),
                AppSpacing.gapXs,
                Text(message, style: context.text.bodySmall),
                AppSpacing.gapMd,
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: Text(actionLabel),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: const [
        Skeleton(width: 200, height: 24),
        SizedBox(height: AppSpacing.sm),
        Skeleton(width: 140, height: 14),
        SizedBox(height: AppSpacing.xxl),
        CardSkeleton(height: 140),
        SizedBox(height: AppSpacing.lg),
        CardSkeleton(height: 110),
        SizedBox(height: AppSpacing.xxl),
        Skeleton(width: 100, height: 18),
        SizedBox(height: AppSpacing.md),
        CardSkeleton(height: 96),
        SizedBox(height: AppSpacing.xxl),
        Skeleton(width: 160, height: 18),
        SizedBox(height: AppSpacing.md),
        TransactionSkeleton(count: 4),
      ],
    );
  }
}
