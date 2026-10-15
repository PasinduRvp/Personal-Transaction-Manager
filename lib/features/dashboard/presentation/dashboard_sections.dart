import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../shared/models/account.dart';
import '../../../shared/models/analytics.dart';
import '../../../shared/models/bill.dart';
import '../../../shared/models/budget.dart';
import '../../../shared/models/savings_goal.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/models/transaction_query.dart';
import '../../../shared/providers/account_providers.dart';
import '../../../shared/providers/transaction_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/charts.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/transaction_tile.dart';

/// The hero balance card.
class BalanceCard extends ConsumerWidget {
  const BalanceCard({super.key, required this.data, this.obscured = false});

  final DashboardData data;
  final bool obscured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final excluded = ref.watch(totalBalanceProvider).excludedCount;

    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.xlAll,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRoutes.accounts),
        splashColor: Colors.white.withValues(alpha: 0.1),
        highlightColor: Colors.white.withValues(alpha: 0.05),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            borderRadius: AppRadius.xlAll,
            gradient: const LinearGradient(
              colors: [Color(0xFF4A7FA7), Color(0xFF1A3D63)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1A3D63).withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              textTheme: Theme.of(context).textTheme.apply(
                    bodyColor: Colors.white,
                    displayColor: Colors.white,
                  ),
              iconTheme: const IconThemeData(color: Colors.white70),
            ),
            child: Builder(
              builder: (context) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Total balance',
                          style: context.text.labelMedium
                              ?.copyWith(color: Colors.white70)),
                      AppSpacing.hGapSm,
                      const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 14,
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                  AppSpacing.gapSm,
                  MoneyText(
                    data.totalBalance,
                    size: MoneySize.hero,
                    obscured: obscured,
                    color: Colors.white,
                  ),
                  if (excluded > 0) ...[
                    AppSpacing.gapSm,
                    Text(
                      '$excluded account${excluded == 1 ? '' : 's'} in another '
                      'currency not included',
                      style: context.text.bodySmall?.copyWith(color: Colors.white70),
                    ),
                  ],
                  AppSpacing.gapLg,
                  const Divider(height: 1, color: Colors.white24),
                  AppSpacing.gapLg,
                  Row(
                    children: [
                      Expanded(
                        child: _MiniStat(
                          label: 'Savings this month',
                          amount: data.monthSummary.savings,
                          obscured: obscured,
                          isPositive: !data.monthSummary.isOverspending,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 34,
                        color: Colors.white24,
                      ),
                      Expanded(
                        child: _SavingsRate(
                          rate: data.monthSummary.savingsRate,
                          hasIncome: !data.monthSummary.income.isZero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.amount,
    required this.isPositive,
    this.obscured = false,
  });

  final String label;
  final Money amount;
  final bool isPositive;
  final bool obscured;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.text.labelMedium?.copyWith(color: Colors.white70)),
        const SizedBox(height: 3),
        MoneyText(
          amount,
          size: MoneySize.row,
          obscured: obscured,
          color: isPositive ? const Color(0xFF4ADE80) : const Color(0xFFFF8585),
        ),
      ],
    );
  }
}

class _SavingsRate extends StatelessWidget {
  const _SavingsRate({required this.rate, required this.hasIncome});

  final double rate;
  final bool hasIncome;

  @override
  Widget build(BuildContext context) {
    // Without income the rate is undefined, not zero; showing "0%" would imply
    // the user saved nothing from earnings they never had.
    final display = hasIncome ? '${rate.toStringAsFixed(rate.abs() >= 10 ? 0 : 1)}%' : '—';
    final color = !hasIncome
        ? context.palette.textTertiary
        : rate >= 20
            ? context.palette.income
            : rate >= 0
                ? context.palette.warning
                : context.palette.expense;

    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Savings rate', style: context.text.labelMedium?.copyWith(color: Colors.white70)),
          const SizedBox(height: 3),
          Text(display, style: context.text.titleMedium?.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// Income, expenses and the month's net.
class MonthSummaryCard extends ConsumerWidget {
  const MonthSummaryCard({
    super.key,
    required this.data,
    this.obscured = false,
  });

  final DashboardData data;
  final bool obscured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  DateDisplay.monthYear(DateTime.now()),
                  style: context.text.titleMedium,
                ),
              ),
              AppChipLabel(
                label: '${data.monthSummary.range.dayCount} days',
                dense: true,
              ),
            ],
          ),
          AppSpacing.gapLg,
          Row(
            children: [
              Expanded(
                child: MoneyTile(
                  label: 'Income',
                  amount: data.monthSummary.income,
                  type: TransactionType.income,
                  icon: Icons.arrow_downward_rounded,
                  changePercent: data.incomeChangePercent,
                  obscured: obscured,
                  onTap: () => _showType(
                    context,
                    ref,
                    TransactionType.income,
                    data.monthSummary.range,
                  ),
                ),
              ),
              AppSpacing.hGapLg,
              Expanded(
                child: MoneyTile(
                  label: 'Spending',
                  amount: data.monthSummary.expenses,
                  type: TransactionType.expense,
                  icon: Icons.arrow_upward_rounded,
                  changePercent: data.expenseChangePercent,
                  obscured: obscured,
                  onTap: () => _showType(
                    context,
                    ref,
                    TransactionType.expense,
                    data.monthSummary.range,
                  ),
                ),
              ),
            ],
          ),
          if (data.monthSummary.isOverspending) ...[
            AppSpacing.gapLg,
            _InlineNotice(
              icon: Icons.trending_down_rounded,
              color: context.palette.expense,
              message: 'You have spent '
                  '${obscured ? '****' : data.monthSummary.savings.abs.format()} more than you '
                  'earned this month.',
            ),
          ],
        ],
      ),
    );
  }
}

/// Shows this month's income or expenses in the transaction list.
void _showType(
  BuildContext context,
  WidgetRef ref,
  TransactionType type,
  DateRange range,
) {
  ref.read(transactionQueryProvider.notifier).apply(
        TransactionQuery(types: {type}, dateRange: range),
      );
  context.go(AppRoutes.transactions);
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.16 : 0.09),
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          AppSpacing.hGapMd,
          Expanded(
            child: Text(
              message,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Prompts the user to finish reviewing imported transactions.
class PendingImportsCard extends StatelessWidget {
  const PendingImportsCard({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => context.push(AppRoutes.importHistory),
      borderColor: context.colors.primary.withValues(alpha: 0.4),
      child: Row(
        children: [
          IconBadge(
            icon: Icons.document_scanner_outlined,
            color: context.colors.primary,
          ),
          AppSpacing.hGapLg,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count == 1
                      ? '1 transaction waiting for review'
                      : '$count transactions waiting for review',
                  style: context.text.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'Check the details, then confirm to add them.',
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: context.palette.textTertiary,
          ),
        ],
      ),
    );
  }
}

/// Budgets at or over their threshold.
class BudgetAlertCard extends StatelessWidget {
  const BudgetAlertCard({super.key, required this.budgets});

  final List<BudgetProgress> budgets;

  @override
  Widget build(BuildContext context) {
    final exceeded = budgets.where((b) => b.isExceeded).toList();
    final warning = budgets.where((b) => !b.isExceeded).toList();
    final isSerious = exceeded.isNotEmpty;
    final color =
        isSerious ? context.palette.danger : context.palette.warning;

    return AppCard(
      onTap: () => context.go(AppRoutes.budgets),
      borderColor: color.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isSerious
                    ? Icons.error_outline_rounded
                    : Icons.warning_amber_rounded,
                size: 18,
                color: color,
              ),
              AppSpacing.hGapSm,
              Expanded(
                child: Text(
                  isSerious
                      ? '${exceeded.length} budget'
                          '${exceeded.length == 1 ? '' : 's'} exceeded'
                      : '${warning.length} budget'
                          '${warning.length == 1 ? '' : 's'} nearly spent',
                  style: context.text.titleSmall?.copyWith(color: color),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: context.palette.textTertiary,
              ),
            ],
          ),
          AppSpacing.gapMd,
          for (final progress in budgets.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      progress.budget.displayName,
                      style: context.text.bodyMedium
                          ?.copyWith(color: context.colors.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${progress.percentUsed.toStringAsFixed(0)}%',
                    style: context.text.titleSmall?.copyWith(
                      color: progress.isExceeded
                          ? context.palette.danger
                          : context.palette.warning,
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

/// Horizontally scrolling account cards.
class AccountsCarousel extends StatelessWidget {
  const AccountsCarousel({
    super.key,
    required this.accounts,
    this.obscured = false,
  });

  final List<Account> accounts;
  final bool obscured;

  @override
  Widget build(BuildContext context) {
    final visible =
        accounts.where((a) => !a.isArchived).toList(growable: false);

    if (visible.isEmpty) {
      return Padding(
        padding: AppSpacing.pageInsets,
        child: AppCard(
          onTap: () => context.push(AppRoutes.accountAdd),
          child: Row(
            children: [
              IconBadge(
                icon: Icons.add_rounded,
                color: context.colors.primary,
              ),
              AppSpacing.hGapLg,
              Expanded(
                child: Text(
                  'Add your first account',
                  style: context.text.titleSmall,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: AppSpacing.pageInsets,
        itemCount: visible.length + 1,
        separatorBuilder: (_, __) => AppSpacing.hGapMd,
        itemBuilder: (context, index) {
          if (index == visible.length) {
            return _AddAccountTile();
          }
          final account = visible[index];
          return _AccountTile(account: account, obscured: obscured);
        },
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.account, required this.obscured});

  final Account account;
  final bool obscured;

  @override
  Widget build(BuildContext context) {
    final utilisation = account.creditUtilisation;

    return SizedBox(
      width: 172,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        onTap: () => context.push(AppRoutes.accountDetail(account.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(icon: account.icon, color: account.color, size: 30),
                AppSpacing.hGapSm,
                Expanded(
                  child: Text(
                    account.name,
                    style: context.text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Spacer(),
            MoneyText.balance(
              account.currentBalance,
              size: MoneySize.row,
              obscured: obscured,
            ),
            const SizedBox(height: 3),
            if (utilisation != null)
              Text(
                '${utilisation.toStringAsFixed(0)}% of limit used',
                style: context.text.labelSmall?.copyWith(
                  letterSpacing: 0,
                  color: utilisation > 80
                      ? context.palette.warning
                      : context.palette.textTertiary,
                ),
              )
            else
              Text(
                account.type.label,
                style: context.text.labelSmall?.copyWith(letterSpacing: 0),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

class _AddAccountTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: InkWell(
        onTap: () => context.push(AppRoutes.accountAdd),
        borderRadius: AppRadius.lgAll,
        child: DottedBorderBox(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_rounded,
                color: context.palette.textTertiary,
                size: 22,
              ),
              AppSpacing.gapSm,
              Text('Add account', style: context.text.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dashed-border container for "add" affordances.
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: context.palette.outlineStrong,
          style: BorderStyle.solid,
          width: 1,
        ),
        color: context.palette.surfaceAlt.withValues(alpha: 0.45),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
        child: child,
      ),
    );
  }
}

/// A donut plus legend of this month's spending.
class SpendingBreakdownCard extends ConsumerWidget {
  const SpendingBreakdownCard({super.key, required this.breakdown});

  final CategoryBreakdown breakdown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slices = breakdown.topWithOther(
      5,
      context.isDark ? AppColors.textTertiaryDark : AppColors.textTertiary,
    );

    return AppCard(
      child: Column(
        children: [
          CategoryDonutChart(
            items: slices,
            total: breakdown.total,
            onSliceTap: (item) => _openCategory(context, ref, item),
          ),
          AppSpacing.gapLg,
          CategoryLegend(
            items: slices,
            total: breakdown.total,
            onTap: (item) => _openCategory(context, ref, item),
          ),
        ],
      ),
    );
  }

  void _openCategory(
    BuildContext context,
    WidgetRef ref,
    CategoryBreakdownItem item,
  ) {
    // The folded "Other" slice has no single category to filter by, so it opens
    // the full breakdown instead of a misleading empty list.
    if (item.categoryId == null) {
      context.go(AppRoutes.analytics);
      return;
    }
    ref.read(transactionQueryProvider.notifier).apply(
          TransactionQuery(
            categoryIds: {item.categoryId!},
            types: const {TransactionType.expense},
            dateRange: breakdown.range,
          ),
        );
    context.go(AppRoutes.transactions);
  }
}

/// Compact budget rows with progress bars.
class BudgetProgressList extends StatelessWidget {
  const BudgetProgressList({
    super.key,
    required this.budgets,
    this.obscured = false,
  });

  final List<BudgetProgress> budgets;
  final bool obscured;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          for (var i = 0; i < budgets.length; i++) ...[
            if (i > 0) ...[
              AppSpacing.gapLg,
              const Divider(height: 1),
              AppSpacing.gapLg,
            ],
            BudgetProgressRow(progress: budgets[i], obscured: obscured),
          ],
        ],
      ),
    );
  }
}

class BudgetProgressRow extends StatelessWidget {
  const BudgetProgressRow({
    super.key,
    required this.progress,
    this.obscured = false,
    this.onTap,
  });

  final BudgetProgress progress;
  final bool obscured;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (progress.health) {
      BudgetHealth.healthy => context.palette.income,
      BudgetHealth.warning => context.palette.warning,
      BudgetHealth.critical => context.palette.warning,
      BudgetHealth.exceeded => context.palette.danger,
    };

    return InkWell(
      onTap: onTap ??
          () => context.push(AppRoutes.budgetDetail(progress.budget.id)),
      borderRadius: AppRadius.smAll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (progress.budget.category != null) ...[
                IconBadge(
                  icon: progress.budget.category!.icon,
                  color: progress.budget.category!.color,
                  size: 30,
                ),
                AppSpacing.hGapMd,
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      progress.budget.displayName,
                      style: context.text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      progress.isExceeded
                          ? 'Over by ${progress.overspend.format()}'
                          : '${progress.remaining.format()} left · '
                              '${progress.daysRemaining} '
                              'day${progress.daysRemaining == 1 ? '' : 's'}',
                      style: context.text.bodySmall?.copyWith(
                        color: progress.isExceeded ? color : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              AppSpacing.hGapMd,
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MoneyText(
                    progress.spent,
                    size: MoneySize.row,
                    obscured: obscured,
                  ),
                  Text(
                    'of ${progress.limit.formatCompact()}',
                    style: context.text.labelSmall?.copyWith(letterSpacing: 0),
                  ),
                ],
              ),
            ],
          ),
          AppSpacing.gapMd,
          ProgressMeter(
            fraction: progress.progressFraction,
            color: color,
            showOverflow: progress.isExceeded,
          ),
        ],
      ),
    );
  }
}

/// Bills due soon.
class UpcomingBillsCard extends StatelessWidget {
  const UpcomingBillsCard({super.key, required this.bills});

  final List<Bill> bills;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        children: [
          for (var i = 0; i < bills.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: AppSpacing.lg),
            _BillRow(bill: bills[i]),
          ],
        ],
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({required this.bill});

  final Bill bill;

  @override
  Widget build(BuildContext context) {
    final isUrgent = bill.isOverdue || bill.isDueToday;
    final color = bill.isOverdue
        ? context.palette.danger
        : bill.isDueToday
            ? context.palette.warning
            : context.palette.textSecondary;

    return ListTile(
      onTap: () => context.push(AppRoutes.bills),
      leading: IconBadge(
        icon: bill.category?.icon ?? Icons.receipt_long_outlined,
        color: bill.category?.color ?? color,
        size: 36,
      ),
      title: Text(bill.name, style: context.text.titleSmall),
      subtitle: Text(
        DateDisplay.dueDescription(bill.dueDate),
        style: context.text.bodySmall?.copyWith(
          color: isUrgent ? color : null,
        ),
      ),
      trailing: MoneyText(bill.amount, size: MoneySize.row),
    );
  }
}

/// Savings goals with progress.
class SavingsGoalsPreview extends StatelessWidget {
  const SavingsGoalsPreview({
    super.key,
    required this.goals,
    this.obscured = false,
  });

  final List<SavingsGoal> goals;
  final bool obscured;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          for (var i = 0; i < goals.length; i++) ...[
            if (i > 0) ...[
              AppSpacing.gapLg,
              const Divider(height: 1),
              AppSpacing.gapLg,
            ],
            SavingsGoalRow(goal: goals[i], obscured: obscured),
          ],
        ],
      ),
    );
  }
}

class SavingsGoalRow extends StatelessWidget {
  const SavingsGoalRow({
    super.key,
    required this.goal,
    this.obscured = false,
  });

  final SavingsGoal goal;
  final bool obscured;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(AppRoutes.savingsDetail(goal.id)),
      borderRadius: AppRadius.smAll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon: goal.icon, color: goal.color, size: 32),
              AppSpacing.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goal.name,
                      style: context.text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      goal.isReached
                          ? 'Goal reached'
                          : '${goal.remaining.format()} to go',
                      style: context.text.bodySmall?.copyWith(
                        color: goal.isReached ? context.palette.income : null,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${goal.progressPercent.toStringAsFixed(goal.progressPercent >= 10 ? 0 : 1)}%',
                style: context.text.titleSmall,
              ),
            ],
          ),
          AppSpacing.gapMd,
          ProgressMeter(
            fraction: goal.progressFraction,
            color: goal.color,
          ),
        ],
      ),
    );
  }
}

/// The recent transactions list.
class RecentTransactionsList extends StatelessWidget {
  const RecentTransactionsList({
    super.key,
    required this.transactions,
    this.obscured = false,
  });

  final List<Transaction> transactions;
  final bool obscured;

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No transactions yet',
        message: 'Start tracking your finances by adding your first '
            'transaction.',
        actionLabel: 'Add transaction',
        onAction: () => context.push(AppRoutes.transactionAdd),
        compact: true,
      );
    }

    return Column(
      children: [
        for (final transaction in transactions)
          TransactionTile(
            transaction: transaction,
            obscureAmount: obscured,
            onTap: () =>
                context.push(AppRoutes.transactionDetail(transaction.id)),
          ),
      ],
    );
  }
}
