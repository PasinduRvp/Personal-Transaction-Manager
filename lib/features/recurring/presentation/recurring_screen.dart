import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../shared/models/subscription.dart';
import '../../../shared/providers/planning_providers.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/state_views.dart';

/// Recurring transaction schedules.
///
/// These post real transactions, unlike subscriptions which only track cost. The
/// posting happens in a scheduled Edge Function so it fires whether or not the
/// app is open — which is why this screen shows the next execution date rather
/// than asking the user to do anything.
class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedules = ref.watch(recurringControllerProvider);
    final obscure = ref.watch(hideAmountsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring'),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.recurringAdd),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'New schedule',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(recurringControllerProvider.notifier).refresh(),
        child: schedules.view(
          (data) {
            if (data.isEmpty) {
              return EmptyState(
                icon: Icons.repeat_rounded,
                title: 'No recurring transactions',
                message: 'Set up your salary, rent or loan payment once and '
                    'Finora will post it automatically.',
                actionLabel: 'New schedule',
                onAction: () => context.push(AppRoutes.recurringAdd),
              );
            }

            final active = data.where((r) => r.isActive).toList()
              ..sort((a, b) =>
                  a.nextExecutionDate.compareTo(b.nextExecutionDate));
            final paused = data.where((r) => !r.isActive).toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.lg,
                AppSpacing.page,
                AppSpacing.xxl,
              ),
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: context.palette.info
                        .withValues(alpha: context.isDark ? 0.16 : 0.09),
                    borderRadius: AppRadius.mdAll,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: context.palette.info,
                      ),
                      AppSpacing.hGapMd,
                      Expanded(
                        child: Text(
                          'These post automatically on their next date, even '
                          'when the app is closed.',
                          style: context.text.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                AppSpacing.gapXl,

                if (active.isNotEmpty) ...[
                  Text(
                    'ACTIVE',
                    style: context.text.labelSmall
                        ?.copyWith(color: context.palette.textSecondary),
                  ),
                  AppSpacing.gapMd,
                  for (final schedule in active)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _RecurringCard(
                        schedule: schedule,
                        obscured: obscure,
                      ),
                    ),
                  AppSpacing.gapLg,
                ],

                if (paused.isNotEmpty) ...[
                  Text(
                    'PAUSED',
                    style: context.text.labelSmall
                        ?.copyWith(color: context.palette.textSecondary),
                  ),
                  AppSpacing.gapMd,
                  for (final schedule in paused)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _RecurringCard(
                        schedule: schedule,
                        obscured: obscure,
                      ),
                    ),
                ],

                AppSpacing.gapLg,
                OutlinedButton.icon(
                  onPressed: () => context.push(AppRoutes.recurringAdd),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New schedule'),
                ),
              ],
            );
          },
          loading: const _RecurringSkeleton(),
          onRetry: () =>
              ref.read(recurringControllerProvider.notifier).refresh(),
        ),
      ),
    );
  }
}

class _RecurringCard extends ConsumerWidget {
  const _RecurringCard({required this.schedule, this.obscured = false});

  final RecurringTransaction schedule;
  final bool obscured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typeColor = switch (schedule.type) {
      TransactionType.income => context.palette.income,
      TransactionType.expense => context.palette.expense,
      TransactionType.transfer => context.palette.transfer,
    };

    final days = schedule.daysUntilNext;

    return AppCard(
      onTap: () => context.push(AppRoutes.recurringEdit(schedule.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: schedule.category?.icon ??
                    switch (schedule.type) {
                      TransactionType.income => Icons.arrow_downward_rounded,
                      TransactionType.expense => Icons.arrow_upward_rounded,
                      TransactionType.transfer => Icons.swap_horiz_rounded,
                    },
                color: schedule.isActive
                    ? (schedule.category?.color ?? typeColor)
                    : context.palette.textTertiary,
                size: 42,
              ),
              AppSpacing.hGapLg,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      schedule.name,
                      style: context.text.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${schedule.frequency.label} · '
                      '${schedule.account?.name ?? 'account removed'}',
                      style: context.text.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              MoneyText.transaction(
                schedule.amount,
                transactionType: schedule.type,
                obscured: obscured,
              ),
            ],
          ),
          AppSpacing.gapLg,
          const Divider(height: 1),
          AppSpacing.gapMd,
          Row(
            children: [
              Icon(
                schedule.isActive
                    ? Icons.schedule_rounded
                    : Icons.pause_circle_outline_rounded,
                size: 15,
                color: context.palette.textTertiary,
              ),
              AppSpacing.hGapSm,
              Expanded(
                child: Text(
                  !schedule.isActive
                      ? 'Paused'
                      : schedule.hasEnded
                          ? 'Schedule has ended'
                          : days <= 0
                              ? 'Due now — posts on the next daily run'
                              : 'Next on '
                                  '${DateDisplay.dayMonthYear(schedule.nextExecutionDate)}'
                                  ' · in $days day${days == 1 ? '' : 's'}',
                  style: context.text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!schedule.autoPost)
                AppChipLabel(
                  label: 'Needs confirming',
                  color: context.palette.warning,
                  dense: true,
                ),
              AppSpacing.hGapSm,
              Switch(
                value: schedule.isActive,
                onChanged: (value) => _toggle(context, ref, value),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    bool active,
  ) async {
    await AppFeedback.runWithProgress(
      context,
      successMessage: active ? 'Schedule resumed' : 'Schedule paused',
      action: () => ref
          .read(recurringControllerProvider.notifier)
          .setActive(schedule.id, active: active),
    );
  }
}

class _RecurringSkeleton extends StatelessWidget {
  const _RecurringSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: const [
        CardSkeleton(height: 60),
        SizedBox(height: AppSpacing.xl),
        CardSkeleton(height: 150),
        SizedBox(height: AppSpacing.md),
        CardSkeleton(height: 150),
      ],
    );
  }
}
