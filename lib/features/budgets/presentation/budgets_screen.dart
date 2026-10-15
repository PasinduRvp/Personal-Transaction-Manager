import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/money.dart';
import '../../../shared/models/budget.dart';
import '../../../shared/providers/planning_providers.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/state_views.dart';
import '../../dashboard/presentation/dashboard_sections.dart';

/// Budgets, with the overall budget first and category budgets ordered by how
/// close each one is to its limit — the ones needing attention at the top.
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetsControllerProvider);
    final currency = ref.watch(currencyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budgets'),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.budgetAdd),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'New budget',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(budgetsControllerProvider.notifier).refresh(),
        child: budgets.view(
          (data) => data.isEmpty
              ? EmptyState(
                  icon: Icons.pie_chart_outline_rounded,
                  title: 'No budgets yet',
                  message: 'Set a monthly limit on a category and Finora will '
                      'warn you before you reach it.',
                  actionLabel: 'Create budget',
                  onAction: () => context.push(AppRoutes.budgetAdd),
                )
              : _BudgetsBody(budgets: data, currency: currency),
          loading: const _BudgetsSkeleton(),
          onRetry: () =>
              ref.read(budgetsControllerProvider.notifier).refresh(),
        ),
      ),
    );
  }
}

class _BudgetsBody extends ConsumerWidget {
  const _BudgetsBody({required this.budgets, required this.currency});

  final List<BudgetProgress> budgets;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final obscure = ref.watch(hideAmountsProvider);

    final overall = budgets.where((b) => b.budget.isOverall).toList();
    final categoryBudgets = budgets.where((b) => !b.budget.isOverall).toList()
      ..sort((a, b) => b.percentUsed.compareTo(a.percentUsed));

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.lg,
        AppSpacing.page,
        AppSpacing.bottomNavClearance,
      ),
      children: [
        _BudgetTotals(budgets: budgets, currency: currency, obscured: obscure),
        AppSpacing.gapXl,

        if (overall.isNotEmpty) ...[
          Text(
            'OVERALL',
            style: context.text.labelSmall
                ?.copyWith(color: context.palette.textSecondary),
          ),
          AppSpacing.gapMd,
          for (final progress in overall)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: AppCard(
                child: BudgetProgressRow(
                  progress: progress,
                  obscured: obscure,
                ),
              ),
            ),
          AppSpacing.gapLg,
        ],

        if (categoryBudgets.isNotEmpty) ...[
          Text(
            'BY CATEGORY',
            style: context.text.labelSmall
                ?.copyWith(color: context.palette.textSecondary),
          ),
          AppSpacing.gapMd,
          for (final progress in categoryBudgets)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: AppCard(
                borderColor: progress.isExceeded
                    ? context.palette.danger.withValues(alpha: 0.35)
                    : null,
                child: BudgetProgressRow(
                  progress: progress,
                  obscured: obscure,
                ),
              ),
            ),
        ],

        AppSpacing.gapLg,
        OutlinedButton.icon(
          onPressed: () => context.push(AppRoutes.budgetAdd),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('New budget'),
        ),
      ],
    );
  }
}

/// Combined budgeted amount, spent and remaining.
class _BudgetTotals extends StatelessWidget {
  const _BudgetTotals({
    required this.budgets,
    required this.currency,
    this.obscured = false,
  });

  final List<BudgetProgress> budgets;
  final String currency;
  final bool obscured;

  @override
  Widget build(BuildContext context) {
    // Only category budgets are summed. Adding an overall budget to the
    // categories it already covers would double-count the same spending.
    final relevant = budgets.where((b) => !b.budget.isOverall).toList();
    final source = relevant.isEmpty ? budgets : relevant;

    var limit = Money.zero(currency);
    var spent = Money.zero(currency);
    for (final progress in source) {
      if (progress.limit.currency != currency) continue;
      limit += progress.limit;
      spent += progress.spent;
    }

    final remaining = limit - spent;
    final fraction = limit.isZero ? 0.0 : (spent.percentOf(limit) / 100);
    final isOver = spent > limit;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  relevant.isEmpty ? 'Budgeted' : 'All category budgets',
                  style: context.text.labelMedium,
                ),
              ),
              AppChipLabel(
                label: '${source.length} '
                    'budget${source.length == 1 ? '' : 's'}',
                dense: true,
              ),
            ],
          ),
          AppSpacing.gapSm,
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              MoneyText(spent, size: MoneySize.hero, obscured: obscured),
              AppSpacing.hGapSm,
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'of ${limit.format()}',
                  style: context.text.bodyMedium,
                ),
              ),
            ],
          ),
          AppSpacing.gapLg,
          ProgressMeter(
            fraction: fraction.clamp(0.0, 1.0),
            color: isOver
                ? context.palette.danger
                : fraction > 0.85
                    ? context.palette.warning
                    : context.palette.income,
            height: 10,
            showOverflow: isOver,
          ),
          AppSpacing.gapMd,
          Text(
            isOver
                ? 'Over budget by ${remaining.abs.format()}'
                : '${remaining.format()} left to spend',
            style: context.text.bodyMedium?.copyWith(
              color: isOver ? context.palette.danger : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetsSkeleton extends StatelessWidget {
  const _BudgetsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: const [
        CardSkeleton(height: 170),
        SizedBox(height: AppSpacing.xl),
        Skeleton(width: 80, height: 12),
        SizedBox(height: AppSpacing.md),
        CardSkeleton(height: 96),
        SizedBox(height: AppSpacing.md),
        CardSkeleton(height: 96),
        SizedBox(height: AppSpacing.md),
        CardSkeleton(height: 96),
      ],
    );
  }
}
