import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../shared/models/lending.dart';
import '../../../shared/providers/planning_providers.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/state_views.dart';

/// Money lent to, or borrowed from, people who are not tracked as accounts.
class LendingScreen extends ConsumerWidget {
  const LendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lendings = ref.watch(lendingControllerProvider);
    final net = ref.watch(lendingNetProvider);
    final obscure = ref.watch(hideAmountsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lending'),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.lendingAdd),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Record lending',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(lendingControllerProvider.notifier).refresh(),
        child: lendings.view(
          (data) {
            if (data.isEmpty) {
              return EmptyState(
                icon: Icons.handshake_outlined,
                title: 'Nothing lent or borrowed',
                message: 'Track money you give or take from friends and '
                    'family, separate from your spending.',
                actionLabel: 'Record lending',
                onAction: () => context.push(AppRoutes.lendingAdd),
              );
            }

            final open = data.where((l) => !l.isSettled).toList();
            final owedToYou = open
                .where((l) => l.kind.isReceivable)
                .toList()
              ..sort(_byDueThenAmount);
            final youOwe = open
                .where((l) => !l.kind.isReceivable)
                .toList()
              ..sort(_byDueThenAmount);
            final settled = data.where((l) => l.isSettled).toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.lg,
                AppSpacing.page,
                AppSpacing.xxl,
              ),
              children: [
                if (!net.isZero) ...[
                  AppCard(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          net.isPositive ? 'Owed to you overall' : 'You owe overall',
                          style: context.text.labelMedium,
                        ),
                        AppSpacing.gapSm,
                        MoneyText(
                          net.abs,
                          size: MoneySize.hero,
                          obscured: obscure,
                          color: net.isPositive
                              ? context.palette.income
                              : context.palette.danger,
                        ),
                      ],
                    ),
                  ),
                  AppSpacing.gapXl,
                ],

                if (owedToYou.isNotEmpty) ...[
                  Text(
                    'OWED TO YOU',
                    style: context.text.labelSmall
                        ?.copyWith(color: context.palette.textSecondary),
                  ),
                  AppSpacing.gapMd,
                  for (final lending in owedToYou)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _LendingCard(lending: lending, obscured: obscure),
                    ),
                  AppSpacing.gapLg,
                ],

                if (youOwe.isNotEmpty) ...[
                  Text(
                    'YOU OWE',
                    style: context.text.labelSmall
                        ?.copyWith(color: context.palette.textSecondary),
                  ),
                  AppSpacing.gapMd,
                  for (final lending in youOwe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _LendingCard(lending: lending, obscured: obscure),
                    ),
                  AppSpacing.gapLg,
                ],

                if (settled.isNotEmpty) ...[
                  Text(
                    'SETTLED',
                    style: context.text.labelSmall
                        ?.copyWith(color: context.palette.textSecondary),
                  ),
                  AppSpacing.gapMd,
                  for (final lending in settled)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _LendingCard(lending: lending, obscured: obscure),
                    ),
                ],

                AppSpacing.gapLg,
                OutlinedButton.icon(
                  onPressed: () => context.push(AppRoutes.lendingAdd),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Record lending'),
                ),
              ],
            );
          },
          loading: const _LendingSkeleton(),
          onRetry: () => ref.read(lendingControllerProvider.notifier).refresh(),
        ),
      ),
    );
  }

  static int _byDueThenAmount(LendingRecord a, LendingRecord b) {
    final aDue = a.dueDate;
    final bDue = b.dueDate;
    if (aDue != null && bDue != null) return aDue.compareTo(bDue);
    if (aDue != null) return -1;
    if (bDue != null) return 1;
    return b.outstanding.compareTo(a.outstanding);
  }
}

class _LendingCard extends StatelessWidget {
  const _LendingCard({required this.lending, this.obscured = false});

  final LendingRecord lending;
  final bool obscured;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => context.push(AppRoutes.lendingDetail(lending.id)),
      borderColor: lending.isOverdue
          ? context.palette.warning.withValues(alpha: 0.4)
          : null,
      child: Row(
        children: [
          IconBadge(icon: lending.icon, color: lending.color, size: 42),
          AppSpacing.hGapLg,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lending.personName,
                  style: context.text.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  lending.isSettled
                      ? 'Settled'
                      : lending.dueDate == null
                          ? 'No due date'
                          : lending.isOverdue
                              ? 'Overdue'
                              : 'Due ${DateDisplay.dayMonthYear(lending.dueDate!)}',
                  style: context.text.bodySmall?.copyWith(
                    color: lending.isOverdue ? context.palette.warning : null,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MoneyText(
                lending.outstanding,
                size: MoneySize.row,
                obscured: obscured,
                color: lending.isSettled
                    ? null
                    : lending.kind.isReceivable
                        ? context.palette.income
                        : context.palette.danger,
              ),
              if (!lending.isSettled)
                Text(
                  'of ${lending.principal.format()}',
                  style: context.text.bodySmall,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LendingSkeleton extends StatelessWidget {
  const _LendingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: const [
        CardSkeleton(height: 110),
        SizedBox(height: AppSpacing.md),
        CardSkeleton(height: 110),
        SizedBox(height: AppSpacing.md),
        CardSkeleton(height: 110),
      ],
    );
  }
}
