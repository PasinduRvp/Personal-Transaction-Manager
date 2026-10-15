import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../shared/models/analytics.dart';
import '../../../shared/providers/analytics_providers.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/charts.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/pickers.dart';
import '../../../shared/widgets/state_views.dart';
import 'drill_down_sheet.dart';

/// The analytics screen.
///
/// Every chart is tappable and drills through to the transactions behind it,
/// because a number a user cannot interrogate is not much use — "I spent 40,000
/// on food" invites the question "on what?".
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(analyticsDataProvider);
    final filter = ref.watch(analyticsFilterProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(filter: filter),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => ref.invalidate(analyticsDataProvider),
                child: data.view(
                  (analytics) => analytics.isEmpty
                      ? _EmptyAnalytics(range: filter.range)
                      : _AnalyticsBody(data: analytics),
                  loading: const _AnalyticsSkeleton(),
                  onRetry: () => ref.invalidate(analyticsDataProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.filter});

  final AnalyticsFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(analyticsFilterProvider.notifier);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Analytics', style: context.text.headlineSmall),
                    const SizedBox(height: 2),
                    Text(filter.range.label, style: context.text.bodyMedium),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => context.push(AppRoutes.reports),
                icon: const Icon(Icons.summarize_outlined),
                tooltip: 'Reports',
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            0,
            AppSpacing.page,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              for (final preset in DateRangePreset.values)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ChoiceChip(
                    label: Text(preset.label),
                    selected: filter.preset == preset,
                    onSelected: (_) async {
                      if (preset == DateRangePreset.custom) {
                        final range = await DateTimePickers.pickRange(
                          context,
                          initial: filter.range,
                        );
                        if (range != null) controller.setCustomRange(range);
                      } else {
                        controller.setPreset(preset);
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnalyticsBody extends ConsumerWidget {
  const _AnalyticsBody({required this.data});

  final AnalyticsData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final obscure = ref.watch(hideAmountsProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        0,
        AppSpacing.page,
        AppSpacing.bottomNavClearance,
      ),
      children: [
        _SummaryCard(data: data, obscured: obscure),
        AppSpacing.gapLg,

        AppSectionCard(
          title: 'Income vs expenses',
          icon: Icons.bar_chart_rounded,
          child: Column(
            children: [
              IncomeExpenseBarChart(
                series: data.monthlyTrend,
                onBarTap: (point) => DrillDownSheet.show(
                  context,
                  drill: DrillDown(
                    type: TransactionType.expense,
                    range: DateRange(
                      AppDateUtils.startOfMonth(point.periodStart),
                      AppDateUtils.endOfMonth(point.periodStart),
                    ),
                    label: 'Spending in ${point.label}',
                  ),
                ),
              ),
              AppSpacing.gapLg,
              ChartLegendRow(
                entries: [
                  (label: 'Income', color: context.palette.income),
                  (label: 'Expenses', color: context.palette.expense),
                ],
              ),
            ],
          ),
        ),
        AppSpacing.gapLg,

        if (!data.expenseBreakdown.isEmpty) ...[
          AppSectionCard(
            title: 'Spending by category',
            subtitle: 'Tap a slice to see the transactions',
            icon: Icons.donut_large_outlined,
            child: Column(
              children: [
                CategoryDonutChart(
                  items: data.expenseBreakdown.topWithOther(
                    6,
                    context.isDark
                        ? AppColors.textTertiaryDark
                        : AppColors.textTertiary,
                  ),
                  total: data.expenseBreakdown.total,
                  onSliceTap: (item) => _drillCategory(context, item),
                ),
                AppSpacing.gapLg,
                CategoryLegend(
                  items: data.expenseBreakdown.items,
                  total: data.expenseBreakdown.total,
                  maxItems: 8,
                  onTap: (item) => _drillCategory(context, item),
                ),
              ],
            ),
          ),
          AppSpacing.gapLg,
        ],

        AppSectionCard(
          title: 'Savings trend',
          subtitle: 'Running total of income minus spending',
          icon: Icons.show_chart_rounded,
          child: TrendLineChart(series: data.monthlyTrend),
        ),
        AppSpacing.gapLg,

        if (data.topMerchants.isNotEmpty) ...[
          AppSectionCard(
            title: 'Top merchants',
            icon: Icons.storefront_outlined,
            child: HorizontalBarList(
              entries: [
                for (var i = 0; i < data.topMerchants.length; i++)
                  (
                    label: data.topMerchants[i].merchant,
                    amount: data.topMerchants[i].total,
                    color: AppColors.categoryPalette[
                        i % AppColors.categoryPalette.length],
                    meta: '${data.topMerchants[i].transactionCount} '
                        'transaction'
                        '${data.topMerchants[i].transactionCount == 1 ? '' : 's'}'
                        ' · avg ${data.topMerchants[i].average.formatCompact()}',
                  ),
              ],
              onTap: (index) => DrillDownSheet.show(
                context,
                drill: DrillDown(
                  type: TransactionType.expense,
                  merchant: data.topMerchants[index].merchant,
                  label: data.topMerchants[index].merchant,
                ),
              ),
            ),
          ),
          AppSpacing.gapLg,
        ],

        if (data.paymentMethods.isNotEmpty) ...[
          AppSectionCard(
            title: 'How you paid',
            icon: Icons.payment_outlined,
            child: HorizontalBarList(
              entries: [
                for (var i = 0; i < data.paymentMethods.length; i++)
                  (
                    label: data.paymentMethods[i].label,
                    amount: data.paymentMethods[i].total,
                    color: AppColors.categoryPalette[
                        (i + 3) % AppColors.categoryPalette.length],
                    meta: '${data.paymentMethods[i].transactionCount} '
                        'transaction'
                        '${data.paymentMethods[i].transactionCount == 1 ? '' : 's'}',
                  ),
              ],
            ),
          ),
          AppSpacing.gapLg,
        ],

        if (!data.incomeBreakdown.isEmpty) ...[
          AppSectionCard(
            title: 'Income sources',
            icon: Icons.arrow_downward_rounded,
            child: CategoryLegend(
              items: data.incomeBreakdown.items,
              total: data.incomeBreakdown.total,
              onTap: (item) => DrillDownSheet.show(
                context,
                drill: DrillDown(
                  type: TransactionType.income,
                  categoryId: item.categoryId,
                  label: item.categoryName,
                ),
              ),
            ),
          ),
          AppSpacing.gapLg,
        ],

        AppSectionCard(
          title: 'Account balances',
          icon: Icons.account_balance_wallet_outlined,
          child: Column(
            children: [
              for (final account in data.accountBalances
                  .where((a) => !a.isArchived))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Row(
                    children: [
                      IconBadge(
                        icon: account.icon,
                        color: account.color,
                        size: 30,
                      ),
                      AppSpacing.hGapMd,
                      Expanded(
                        child: Text(
                          account.name,
                          style: context.text.bodyMedium
                              ?.copyWith(color: context.colors.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      MoneyText.balance(
                        account.currentBalance,
                        size: MoneySize.row,
                        obscured: obscure,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        if (data.largestExpense != null) ...[
          AppSpacing.gapLg,
          AppSectionCard(
            title: 'Largest expense',
            icon: Icons.trending_up_rounded,
            child: Row(
              children: [
                IconBadge(
                  icon: data.largestExpense!.icon,
                  color: data.largestExpense!.category?.color ??
                      context.palette.expense,
                ),
                AppSpacing.hGapLg,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.largestExpense!.title,
                        style: context.text.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        DateDisplay.dayMonthYear(
                          data.largestExpense!.transactionDate,
                        ),
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
                MoneyText(
                  data.largestExpense!.amount,
                  size: MoneySize.large,
                  obscured: obscure,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _drillCategory(BuildContext context, CategoryBreakdownItem item) {
    // The "Other" slice has no single category to drill into.
    if (item.categoryId == null) return;
    DrillDownSheet.show(
      context,
      drill: DrillDown(
        type: TransactionType.expense,
        categoryId: item.categoryId,
        label: item.categoryName,
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.data, this.obscured = false});

  final AnalyticsData data;
  final bool obscured;

  @override
  Widget build(BuildContext context) {
    final summary = data.summary;
    final previous = data.previousSummary;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  summary.isOverspending ? 'Overspent by' : 'Saved',
                  style: context.text.labelMedium,
                ),
              ),
              AppChipLabel(
                label: '${data.transactionCount} transactions',
                dense: true,
              ),
            ],
          ),
          AppSpacing.gapSm,
          MoneyText(
            summary.savings.abs,
            size: MoneySize.hero,
            obscured: obscured,
            color: summary.isOverspending
                ? context.palette.expense
                : context.palette.income,
          ),
          if (!summary.income.isZero) ...[
            AppSpacing.gapXs,
            Text(
              '${summary.savingsRate.toStringAsFixed(summary.savingsRate.abs() >= 10 ? 0 : 1)}% '
              'of income',
              style: context.text.bodySmall,
            ),
          ],
          AppSpacing.gapLg,
          const Divider(height: 1),
          AppSpacing.gapLg,
          Row(
            children: [
              Expanded(
                child: MoneyTile(
                  label: 'Income',
                  amount: summary.income,
                  type: TransactionType.income,
                  changePercent: CashflowSummary.changePercent(
                    summary.income,
                    previous.income,
                  ),
                  obscured: obscured,
                ),
              ),
              AppSpacing.hGapLg,
              Expanded(
                child: MoneyTile(
                  label: 'Expenses',
                  amount: summary.expenses,
                  type: TransactionType.expense,
                  changePercent: CashflowSummary.changePercent(
                    summary.expenses,
                    previous.expenses,
                  ),
                  obscured: obscured,
                ),
              ),
            ],
          ),
          AppSpacing.gapLg,
          Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 14,
                color: context.palette.textTertiary,
              ),
              AppSpacing.hGapSm,
              Expanded(
                child: Text(
                  'Averaging ${summary.averageDailySpend.format()} a day over '
                  '${summary.range.dayCount} days',
                  style: context.text.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyAnalytics extends StatelessWidget {
  const _EmptyAnalytics({required this.range});

  final DateRange range;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.insights_outlined,
      title: 'Nothing to analyse yet',
      message: 'There are no transactions in ${range.label}. Add some, or pick '
          'a different period.',
      actionLabel: 'Add transaction',
      onAction: () => context.push(AppRoutes.transactionAdd),
    );
  }
}

class _AnalyticsSkeleton extends StatelessWidget {
  const _AnalyticsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: const [
        CardSkeleton(height: 230),
        SizedBox(height: AppSpacing.lg),
        CardSkeleton(height: 300),
        SizedBox(height: AppSpacing.lg),
        CardSkeleton(height: 340),
      ],
    );
  }
}
