import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../shared/models/account.dart';
import '../../../shared/models/analytics.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/models/transaction_query.dart';
import '../../../shared/providers/account_providers.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/providers/repository_providers.dart';
import '../../../shared/providers/transaction_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/transaction_tile.dart';

/// One account: its balance, this month's activity, and its recent
/// transactions.
class AccountDetailScreen extends ConsumerWidget {
  const AccountDetailScreen({super.key, required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountByIdProvider(accountId));
    final accounts = ref.watch(accountsControllerProvider);

    if (account == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Account')),
        body: accounts.view(
          (_) => const EmptyState(
            icon: Icons.search_off_rounded,
            title: 'Account not found',
            message: 'It may have been deleted.',
          ),
          loading: const LoadingView(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(account.name),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.accountEdit(account.id)),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) async {
              switch (value) {
                case 'archive':
                  final archiving = !account.isArchived;
                  final confirmed = await AppFeedback.confirm(
                    context,
                    title: archiving ? 'Archive account?' : 'Restore account?',
                    message: archiving
                        ? 'Its transactions stay in your history, and it stops appearing when you add a transaction.'
                        : 'It will appear again when you add a transaction.',
                    confirmLabel: archiving ? 'Archive' : 'Restore',
                  );
                  if (!confirmed || !context.mounted) return;
                  await AppFeedback.runWithProgress(
                    context,
                    successMessage: archiving ? 'Account archived' : 'Account restored',
                    action: () => ref
                        .read(accountsControllerProvider.notifier)
                        .setArchived(account.id, archived: archiving),
                  );
                case 'delete':
                  final count = await ref
                      .read(accountRepositoryProvider)
                      .transactionCount(account.id);
                  if (!context.mounted) return;
                  bool force = false;
                  if (count > 0) {
                    final choice = await showDialog<String>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete Account?'),
                        content: Text(
                          'This account has $count transaction${count == 1 ? '' : 's'}.\n\n'
                          'Archiving will hide the account while keeping transaction history intact. '
                          'Deleting will permanently remove this account.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, 'cancel'),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, 'archive'),
                            child: const Text('Archive instead'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: context.palette.danger,
                            ),
                            onPressed: () => Navigator.pop(context, 'delete'),
                            child: const Text('Delete anyway'),
                          ),
                        ],
                      ),
                    );
                    if (choice == 'archive' && context.mounted) {
                      await ref
                          .read(accountsControllerProvider.notifier)
                          .setArchived(account.id, archived: true);
                      return;
                    }
                    if (choice != 'delete') return;
                    force = true;
                  } else {
                    final confirmed = await AppFeedback.confirm(
                      context,
                      title: 'Delete account?',
                      message: 'Are you sure you want to delete "${account.name}"?',
                      confirmLabel: 'Delete',
                      isDestructive: true,
                    );
                    if (!confirmed || !context.mounted) return;
                  }
                  if (!context.mounted) return;
                  final done = await AppFeedback.runWithProgress(
                    context,
                    successMessage: 'Account deleted',
                    action: () async {
                      await ref
                          .read(accountsControllerProvider.notifier)
                          .delete(account.id, force: force);
                      return true;
                    },
                  );
                  if (done == true && context.mounted) context.pop();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'archive',
                child: ListTile(
                  leading: Icon(
                    account.isArchived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                  ),
                  title: Text(account.isArchived ? 'Restore' : 'Archive'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: context.palette.danger,
                  ),
                  title: Text(
                    'Delete',
                    style: TextStyle(color: context.palette.danger),
                  ),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(accountActivityProvider(accountId));
          ref.invalidate(accountTransactionsProvider(accountId));
          await ref.read(accountsControllerProvider.notifier).refresh();
        },
        child: _Body(account: account),
      ),
    );
  }
}

/// This month's income and spending on one account.
final accountActivityProvider =
    FutureProvider.family<CashflowSummary, String>((ref, accountId) {
  final currency = ref.watch(currencyProvider);
  return ref.watch(analyticsRepositoryProvider).fetchCashflow(
        range: AppDateUtils.thisMonth(),
        currency: currency,
        accountIds: {accountId},
      );
});

/// Recent transactions on one account.
final accountTransactionsProvider =
    FutureProvider.family<List<Transaction>, String>((ref, accountId) async {
  final page = await ref.watch(transactionRepositoryProvider).fetchPage(
        query: TransactionQuery(accountIds: {accountId}),
        pageSize: 12,
      );
  return page.items;
});

class _Body extends ConsumerWidget {
  const _Body({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(accountActivityProvider(account.id));
    final transactions = ref.watch(accountTransactionsProvider(account.id));
    final obscure = ref.watch(hideAmountsProvider);

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: Column(
            children: [
              AppCard(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  children: [
                    IconBadge(
                      icon: account.icon,
                      color: account.color,
                      size: 56,
                    ),
                    AppSpacing.gapLg,
                    Text(
                      account.type.isCredit
                          ? 'Current balance'
                          : 'Available balance',
                      style: context.text.labelMedium,
                    ),
                    AppSpacing.gapXs,
                    MoneyText.balance(
                      account.currentBalance,
                      size: MoneySize.hero,
                      obscured: obscure,
                    ),
                    AppSpacing.gapSm,
                    Text(account.subtitle, style: context.text.bodySmall),
                    if (account.type.isCredit &&
                        account.creditLimit != null) ...[
                      AppSpacing.gapLg,
                      _CreditUsage(account: account),
                    ],
                  ],
                ),
              ),
              AppSpacing.gapLg,

              activity.view(
                (summary) => AppCard(
                  child: Column(
                    children: [
                      Text(
                        DateDisplay.monthYear(DateTime.now()),
                        style: context.text.labelMedium,
                      ),
                      AppSpacing.gapLg,
                      Row(
                        children: [
                          Expanded(
                            child: MoneyTile(
                              label: 'Money in',
                              amount: summary.income,
                              type: TransactionType.income,
                              obscured: obscure,
                            ),
                          ),
                          AppSpacing.hGapLg,
                          Expanded(
                            child: MoneyTile(
                              label: 'Money out',
                              amount: summary.expenses,
                              type: TransactionType.expense,
                              obscured: obscure,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                loading: const CardSkeleton(height: 110),
                errorCompact: true,
              ),
              AppSpacing.gapLg,

              AppCard(
                child: Column(
                  children: [
                    DetailRow(
                      label: 'Opening balance',
                      icon: Icons.flag_outlined,
                      valueWidget: MoneyText.balance(
                        account.initialBalance,
                        size: MoneySize.row,
                        obscured: obscure,
                      ),
                    ),
                    const Divider(height: 1),
                    DetailRow(
                      label: 'Currency',
                      icon: Icons.language_rounded,
                      value: account.currency,
                    ),
                    const Divider(height: 1),
                    DetailRow(
                      label: 'Type',
                      icon: Icons.category_outlined,
                      value: account.type.label,
                    ),
                    if (account.institutionName != null) ...[
                      const Divider(height: 1),
                      DetailRow(
                        label: 'Provider',
                        icon: Icons.account_balance_outlined,
                        value: account.institutionName,
                      ),
                    ],
                    const Divider(height: 1),
                    DetailRow(
                      label: 'Added',
                      icon: Icons.event_outlined,
                      value: DateDisplay.dayMonthYear(account.createdAt),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        SectionHeading(
          title: 'Transactions',
          actionLabel: 'See all',
          onAction: () {
            ref.read(transactionQueryProvider.notifier).apply(
                  TransactionQuery(accountIds: {account.id}),
                );
            context.go(AppRoutes.transactions);
          },
        ),
        transactions.view(
          (data) => data.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No transactions yet',
                  message: 'Transactions on this account will appear here.',
                  compact: true,
                )
              : Column(
                  children: [
                    for (final transaction in data)
                      TransactionTile(
                        transaction: transaction,
                        showAccount: false,
                        obscureAmount: obscure,
                        onTap: () => context.push(
                          AppRoutes.transactionDetail(transaction.id),
                        ),
                      ),
                  ],
                ),
          loading: const TransactionSkeleton(count: 4),
          onRetry: () => ref.invalidate(
            accountTransactionsProvider(account.id),
          ),
        ),
      ],
    );
  }
}

/// Credit card utilisation, with a bar that turns amber as the limit nears.
class _CreditUsage extends StatelessWidget {
  const _CreditUsage({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final utilisation = account.creditUtilisation ?? 0;
    final available = account.availableCredit;

    final color = utilisation >= 90
        ? context.palette.danger
        : utilisation >= 70
            ? context.palette.warning
            : context.palette.income;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${utilisation.toStringAsFixed(0)}% of '
                '${account.creditLimit!.formatCompact()} used',
                style: context.text.bodySmall,
              ),
            ),
            if (available != null)
              Text(
                '${available.format()} available',
                style: context.text.labelMedium?.copyWith(color: color),
              ),
          ],
        ),
        AppSpacing.gapSm,
        ProgressMeter(
          fraction: (utilisation / 100).clamp(0.0, 1.0),
          color: color,
          showOverflow: utilisation > 100,
        ),
      ],
    );
  }
}
