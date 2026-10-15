import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../shared/models/savings_goal.dart';
import '../../../shared/providers/planning_providers.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/state_views.dart';

/// Savings goals, active first.
class SavingsScreen extends ConsumerWidget {
  const SavingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(savingsControllerProvider);
    final totals = ref.watch(savingsTotalsProvider);
    final obscure = ref.watch(hideAmountsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Savings goals'),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.savingsAdd),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'New goal',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(savingsControllerProvider.notifier).refresh(),
        child: goals.view(
          (data) {
            if (data.isEmpty) {
              return EmptyState(
                icon: Icons.savings_outlined,
                title: 'No savings goals yet',
                message: 'Set a target and watch it fill up as you put money '
                    'aside.',
                actionLabel: 'Create goal',
                onAction: () => context.push(AppRoutes.savingsAdd),
              );
            }

            final active =
                data.where((g) => !g.isCompleted && !g.isArchived).toList();
            final completed =
                data.where((g) => g.isCompleted && !g.isArchived).toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.lg,
                AppSpacing.page,
                AppSpacing.xxl,
              ),
              children: [
                if (!totals.target.isZero) ...[
                  AppCard(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Saved across all goals',
                          style: context.text.labelMedium,
                        ),
                        AppSpacing.gapSm,
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            MoneyText(
                              totals.saved,
                              size: MoneySize.hero,
                              obscured: obscure,
                            ),
                            AppSpacing.hGapSm,
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                'of ${totals.target.format()}',
                                style: context.text.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                        AppSpacing.gapLg,
                        ProgressMeter(
                          fraction: (totals.percent / 100).clamp(0.0, 1.0),
                          color: context.colors.primary,
                          height: 10,
                        ),
                        AppSpacing.gapMd,
                        Text(
                          '${totals.percent.toStringAsFixed(totals.percent >= 10 ? 0 : 1)}% '
                          'of your targets reached',
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  AppSpacing.gapXl,
                ],

                for (final goal in active)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _GoalCard(goal: goal, obscured: obscure),
                  ),

                if (completed.isNotEmpty) ...[
                  AppSpacing.gapLg,
                  Text(
                    'COMPLETED',
                    style: context.text.labelSmall
                        ?.copyWith(color: context.palette.textSecondary),
                  ),
                  AppSpacing.gapMd,
                  for (final goal in completed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _GoalCard(goal: goal, obscured: obscure),
                    ),
                ],

                AppSpacing.gapLg,
                OutlinedButton.icon(
                  onPressed: () => context.push(AppRoutes.savingsAdd),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New goal'),
                ),
              ],
            );
          },
          loading: const _SavingsSkeleton(),
          onRetry: () =>
              ref.read(savingsControllerProvider.notifier).refresh(),
        ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, this.obscured = false});

  final SavingsGoal goal;
  final bool obscured;

  @override
  Widget build(BuildContext context) {
    final required = goal.requiredMonthlyContribution;

    return AppCard(
      onTap: () => context.push(AppRoutes.savingsDetail(goal.id)),
      borderColor: goal.isOverdue
          ? context.palette.warning.withValues(alpha: 0.4)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon: goal.icon, color: goal.color, size: 42),
              AppSpacing.hGapLg,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            goal.name,
                            style: context.text.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (goal.isCompleted)
                          AppChipLabel(
                            label: 'Complete',
                            color: context.palette.income,
                            icon: Icons.check_rounded,
                            dense: true,
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      goal.targetDate == null
                          ? 'No target date'
                          : goal.isOverdue
                              ? 'Target date passed '
                                  '${DateDisplay.relative(goal.targetDate!)}'
                              : 'Target ${DateDisplay.dayMonthYear(goal.targetDate!)}',
                      style: context.text.bodySmall?.copyWith(
                        color: goal.isOverdue ? context.palette.warning : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          AppSpacing.gapLg,
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MoneyText(
                      goal.currentAmount,
                      size: MoneySize.large,
                      obscured: obscured,
                    ),
                    Text(
                      'of ${goal.targetAmount.format()}',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                '${goal.progressPercent.toStringAsFixed(goal.progressPercent >= 10 ? 0 : 1)}%',
                style: context.text.titleLarge?.copyWith(color: goal.color),
              ),
            ],
          ),
          AppSpacing.gapMd,
          ProgressMeter(fraction: goal.progressFraction, color: goal.color),
          if (required != null && !goal.isCompleted) ...[
            AppSpacing.gapMd,
            Row(
              children: [
                Icon(
                  Icons.trending_up_rounded,
                  size: 14,
                  color: context.palette.textTertiary,
                ),
                AppSpacing.hGapSm,
                Expanded(
                  child: Text(
                    'Set aside ${required.format()} a month to hit your target',
                    style: context.text.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SavingsSkeleton extends StatelessWidget {
  const _SavingsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: const [
        CardSkeleton(height: 180),
        SizedBox(height: AppSpacing.xl),
        CardSkeleton(height: 160),
        SizedBox(height: AppSpacing.md),
        CardSkeleton(height: 160),
      ],
    );
  }
}
