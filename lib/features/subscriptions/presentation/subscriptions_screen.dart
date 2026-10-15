import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/models/subscription.dart';
import '../../../shared/providers/planning_providers.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/state_views.dart';

/// Subscriptions, with the running monthly and yearly cost.
///
/// The totals normalise across billing periods, so a yearly plan and a monthly
/// one can be added together — the figure a user actually wants is "what do my
/// subscriptions cost me a month".
class SubscriptionsScreen extends ConsumerWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptions = ref.watch(subscriptionsControllerProvider);
    final totals = ref.watch(subscriptionTotalsProvider);
    final obscure = ref.watch(hideAmountsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscriptions'),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.subscriptionAdd),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add subscription',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(subscriptionsControllerProvider.notifier).refresh(),
        child: subscriptions.view(
          (data) {
            if (data.isEmpty) {
              return EmptyState(
                icon: Icons.subscriptions_outlined,
                title: 'No subscriptions tracked',
                message: 'Add your recurring services to see what they cost you '
                    'each month.',
                actionLabel: 'Add subscription',
                onAction: () => context.push(AppRoutes.subscriptionAdd),
              );
            }

            final active = data.where((s) => s.isActive).toList()
              ..sort((a, b) =>
                  a.daysUntilRenewal.compareTo(b.daysUntilRenewal));
            final paused = data.where((s) => !s.isActive).toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.lg,
                AppSpacing.page,
                AppSpacing.xxl,
              ),
              children: [
                AppCard(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Monthly subscription cost',
                        style: context.text.labelMedium,
                      ),
                      AppSpacing.gapSm,
                      MoneyText(
                        totals.monthly,
                        size: MoneySize.hero,
                        obscured: obscure,
                      ),
                      AppSpacing.gapLg,
                      const Divider(height: 1),
                      AppSpacing.gapLg,
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Per year',
                                  style: context.text.labelMedium,
                                ),
                                const SizedBox(height: 3),
                                MoneyText(
                                  totals.yearly,
                                  size: MoneySize.row,
                                  obscured: obscure,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 32,
                            color: context.colors.outline,
                          ),
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.only(left: AppSpacing.lg),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Active',
                                    style: context.text.labelMedium,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${totals.activeCount}',
                                    style: context.text.titleMedium,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
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
                  AppCard(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Column(
                      children: [
                        for (var i = 0; i < active.length; i++) ...[
                          if (i > 0)
                            const Divider(height: 1, indent: AppSpacing.lg),
                          _SubscriptionRow(
                            subscription: active[i],
                            obscured: obscure,
                          ),
                        ],
                      ],
                    ),
                  ),
                  AppSpacing.gapXl,
                ],

                if (paused.isNotEmpty) ...[
                  Text(
                    'PAUSED',
                    style: context.text.labelSmall
                        ?.copyWith(color: context.palette.textSecondary),
                  ),
                  AppSpacing.gapMd,
                  AppCard(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Column(
                      children: [
                        for (var i = 0; i < paused.length; i++) ...[
                          if (i > 0)
                            const Divider(height: 1, indent: AppSpacing.lg),
                          _SubscriptionRow(
                            subscription: paused[i],
                            obscured: obscure,
                          ),
                        ],
                      ],
                    ),
                  ),
                  AppSpacing.gapXl,
                ],

                OutlinedButton.icon(
                  onPressed: () => context.push(AppRoutes.subscriptionAdd),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add subscription'),
                ),
              ],
            );
          },
          loading: const _SubscriptionsSkeleton(),
          onRetry: () =>
              ref.read(subscriptionsControllerProvider.notifier).refresh(),
        ),
      ),
    );
  }
}

class _SubscriptionRow extends ConsumerWidget {
  const _SubscriptionRow({required this.subscription, this.obscured = false});

  final Subscription subscription;
  final bool obscured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = subscription.daysUntilRenewal;
    final renewsSoon = subscription.renewsSoon;

    return ListTile(
      onTap: () => context.push(AppRoutes.subscriptionEdit(subscription.id)),
      leading: IconBadge(
        icon: subscription.category?.icon ?? Icons.subscriptions_outlined,
        color: subscription.isActive
            ? (subscription.category?.color ?? context.colors.primary)
            : context.palette.textTertiary,
      ),
      title: Text(
        subscription.name,
        style: context.text.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subscription.isActive
            ? '${subscription.frequency.label} · '
                '${days < 0 ? 'renewal due' : days == 0 ? 'renews today' : 'renews in $days day${days == 1 ? '' : 's'}'}'
            : 'Paused',
        style: context.text.bodySmall?.copyWith(
          color: renewsSoon ? context.palette.warning : null,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          MoneyText(
            subscription.amount,
            size: MoneySize.row,
            obscured: obscured,
          ),
          // The normalised monthly figure is only worth showing when it differs
          // from the billed amount.
          if (subscription.frequency.wire != 'MONTHLY')
            Text(
              '${subscription.monthlyCost.formatCompact()}/mo',
              style: context.text.labelSmall?.copyWith(letterSpacing: 0),
            ),
        ],
      ),
    );
  }
}

class _SubscriptionsSkeleton extends StatelessWidget {
  const _SubscriptionsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: const [
        CardSkeleton(height: 180),
        SizedBox(height: AppSpacing.xl),
        Skeleton(width: 70, height: 12),
        SizedBox(height: AppSpacing.md),
        CardSkeleton(height: 220),
      ],
    );
  }
}
