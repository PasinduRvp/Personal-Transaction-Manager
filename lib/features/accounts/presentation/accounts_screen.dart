import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/money.dart';
import '../../../shared/models/account.dart';
import '../../../shared/providers/account_providers.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/state_views.dart';

/// All accounts, grouped by type, with the combined balance at the top.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsControllerProvider);
    final currency = ref.watch(currencyProvider);
    final balance = ref.watch(totalBalanceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.accountAdd),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add account',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(accountsControllerProvider.notifier).refresh(),
        child: accounts.view(
          (data) {
            if (data.isEmpty) {
              return EmptyState(
                icon: Icons.account_balance_wallet_outlined,
                title: 'No accounts yet',
                message: 'Add the accounts you spend from so Finora can track '
                    'your balances.',
                actionLabel: 'Add account',
                onAction: () => context.push(AppRoutes.accountAdd),
              );
            }
            return _AccountsList(
              accounts: data,
              currency: currency,
              total: balance.total,
              excludedCount: balance.excludedCount,
            );
          },
          loading: const _AccountsSkeleton(),
          onRetry: () =>
              ref.read(accountsControllerProvider.notifier).refresh(),
        ),
      ),
    );
  }
}

class _AccountsList extends ConsumerWidget {
  const _AccountsList({
    required this.accounts,
    required this.currency,
    required this.total,
    required this.excludedCount,
  });

  final List<Account> accounts;
  final String currency;
  final Money total;
  final int excludedCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = accounts.where((a) => !a.isArchived).toList();
    final archived = accounts.where((a) => a.isArchived).toList();

    // Grouped by type so a user with a dozen accounts can find one, and the
    // group totals answer "how much is in the bank" without arithmetic.
    final grouped = <AccountType, List<Account>>{};
    for (final account in active) {
      grouped.putIfAbsent(account.type, () => []).add(account);
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        Container(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Combined balance',
                style: context.text.labelMedium?.copyWith(color: Colors.white70),
              ),
              AppSpacing.gapSm,
              Theme(
                data: Theme.of(context).copyWith(
                  textTheme: Theme.of(context).textTheme.apply(
                        bodyColor: Colors.white,
                        displayColor: Colors.white,
                      ),
                ),
                child: Builder(
                  builder: (context) => MoneyText(
                    total,
                    size: MoneySize.hero,
                    color: Colors.white,
                  ),
                ),
              ),
              if (excludedCount > 0) ...[
                AppSpacing.gapSm,
                Text(
                  '$excludedCount account${excludedCount == 1 ? '' : 's'} in '
                  'another currency not included',
                  style: context.text.bodySmall?.copyWith(color: Colors.white70),
                ),
              ],
              AppSpacing.gapMd,
              Text(
                '${active.length} active account'
                '${active.length == 1 ? '' : 's'}',
                style: context.text.bodySmall?.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
        AppSpacing.gapXl,

        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(
              bottom: AppSpacing.md,
              top: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    entry.key.label,
                    style: context.text.labelSmall
                        ?.copyWith(color: context.palette.textSecondary),
                  ),
                ),
                MoneyText(
                  _groupTotal(entry.value, currency),
                  size: MoneySize.small,
                ),
              ],
            ),
          ),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (var i = 0; i < entry.value.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: AppSpacing.lg),
                  _AccountRow(account: entry.value[i]),
                ],
              ],
            ),
          ),
          AppSpacing.gapLg,
        ],

        if (archived.isNotEmpty) ...[
          AppSpacing.gapMd,
          _ArchivedSection(accounts: archived),
        ],

        AppSpacing.gapXl,
        OutlinedButton.icon(
          onPressed: () => context.push(AppRoutes.accountAdd),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add account'),
        ),
        AppSpacing.gapXxl,
      ],
    );
  }

  static Money _groupTotal(List<Account> accounts, String currency) {
    var total = Money.zero(currency);
    for (final account in accounts) {
      if (account.currency == currency) total += account.currentBalance;
    }
    return total;
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final utilisation = account.creditUtilisation;

    return ListTile(
      onTap: () => context.push(AppRoutes.accountDetail(account.id)),
      leading: IconBadge(icon: account.icon, color: account.color),
      title: Row(
        children: [
          Expanded(
            child: Text(
              account.name,
              style: context.text.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!account.isActive)
            AppChipLabel(
              label: 'Inactive',
              color: context.palette.textTertiary,
              dense: true,
            ),
        ],
      ),
      subtitle: Text(
        utilisation != null
            ? '${account.subtitle} · ${utilisation.toStringAsFixed(0)}% used'
            : account.subtitle,
        style: context.text.bodySmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          MoneyText.balance(account.currentBalance, size: MoneySize.row),
          if (account.availableCredit != null)
            Text(
              '${account.availableCredit!.formatCompact()} available',
              style: context.text.labelSmall?.copyWith(letterSpacing: 0),
            ),
        ],
      ),
    );
  }
}

class _ArchivedSection extends ConsumerStatefulWidget {
  const _ArchivedSection({required this.accounts});

  final List<Account> accounts;

  @override
  ConsumerState<_ArchivedSection> createState() => _ArchivedSectionState();
}

class _ArchivedSectionState extends ConsumerState<_ArchivedSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: AppRadius.smAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                Icon(
                  Icons.archive_outlined,
                  size: 16,
                  color: context.palette.textTertiary,
                ),
                AppSpacing.hGapSm,
                Text(
                  'Archived (${widget.accounts.length})',
                  style: context.text.titleSmall,
                ),
                AppSpacing.hGapSm,
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: context.palette.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          AppSpacing.gapSm,
          Text(
            'Archived accounts keep their transactions but no longer appear '
            'when you add one.',
            style: context.text.bodySmall,
          ),
          AppSpacing.gapMd,
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (var i = 0; i < widget.accounts.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: AppSpacing.lg),
                  ListTile(
                    leading: IconBadge(
                      icon: widget.accounts[i].icon,
                      color: context.palette.textTertiary,
                    ),
                    title: Text(
                      widget.accounts[i].name,
                      style: context.text.titleSmall,
                    ),
                    subtitle: Text(
                      widget.accounts[i].subtitle,
                      style: context.text.bodySmall,
                    ),
                    trailing: TextButton(
                      onPressed: () => _restore(widget.accounts[i]),
                      child: const Text('Restore'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _restore(Account account) async {
    await AppFeedback.runWithProgress(
      context,
      successMessage: '${account.name} restored',
      action: () => ref
          .read(accountsControllerProvider.notifier)
          .setArchived(account.id, archived: false),
    );
  }
}

class _AccountsSkeleton extends StatelessWidget {
  const _AccountsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: const [
        CardSkeleton(height: 130),
        SizedBox(height: AppSpacing.xl),
        Skeleton(width: 90, height: 12),
        SizedBox(height: AppSpacing.md),
        CardSkeleton(height: 150),
        SizedBox(height: AppSpacing.xl),
        Skeleton(width: 90, height: 12),
        SizedBox(height: AppSpacing.md),
        CardSkeleton(height: 90),
      ],
    );
  }
}
