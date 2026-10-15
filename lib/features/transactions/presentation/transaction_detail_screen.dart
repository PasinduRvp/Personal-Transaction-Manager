import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/providers/ocr_providers.dart';
import '../../../shared/providers/transaction_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/transaction_tile.dart';

/// A single transaction, with everything known about it and what can be done.
class TransactionDetailScreen extends ConsumerWidget {
  const TransactionDetailScreen({super.key, required this.transactionId});

  final String transactionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transaction = ref.watch(transactionDetailProvider(transactionId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction'),
        actions: [
          transaction.maybeWhen(
            data: (data) => _ActionsMenu(transaction: data),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: transaction.view(
        (data) => _Body(transaction: data),
        onRetry: () => ref.invalidate(transactionDetailProvider(transactionId)),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        _AmountHeader(transaction: transaction),
        AppSpacing.gapXl,

        if (transaction.isPending) ...[
          _PendingBanner(transaction: transaction),
          AppSpacing.gapLg,
        ],

        if (transaction.hasSplitMismatch) ...[
          SplitMismatchBanner(
            total: transaction.amount,
            splitTotal: transaction.splitTotal,
          ),
          AppSpacing.gapLg,
        ],

        AppCard(
          child: Column(
            children: [
              DetailRow(
                label: 'Type',
                icon: Icons.category_outlined,
                valueWidget: AppChipLabel(
                  label: transaction.type.label,
                  color: switch (transaction.type) {
                    TransactionType.income => context.palette.income,
                    TransactionType.expense => context.palette.expense,
                    TransactionType.transfer => context.palette.transfer,
                  },
                ),
              ),
              const Divider(height: 1),
              DetailRow(
                label: transaction.type.isTransfer
                    ? (transaction.transferDirection ==
                            TransferDirection.incoming
                        ? 'Into'
                        : 'From')
                    : 'Account',
                icon: Icons.account_balance_wallet_outlined,
                value: transaction.account?.name,
                onTap: transaction.account == null
                    ? null
                    : () => context.push(
                          AppRoutes.accountDetail(transaction.accountId),
                        ),
              ),
              if (transaction.transferPeerAccount != null) ...[
                const Divider(height: 1),
                DetailRow(
                  label: transaction.transferDirection ==
                          TransferDirection.incoming
                      ? 'From'
                      : 'To',
                  icon: Icons.swap_horiz_rounded,
                  value: transaction.transferPeerAccount!.name,
                ),
              ],
              if (!transaction.type.isTransfer) ...[
                const Divider(height: 1),
                DetailRow(
                  label: 'Category',
                  icon: Icons.label_outline_rounded,
                  valueWidget: transaction.category == null
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              transaction.category!.icon,
                              size: 16,
                              color: transaction.category!.color,
                            ),
                            AppSpacing.hGapSm,
                            Text(
                              transaction.category!.name,
                              style: context.text.titleSmall,
                            ),
                          ],
                        ),
                  value: transaction.category == null ? 'Uncategorised' : null,
                ),
              ],
              const Divider(height: 1),
              DetailRow(
                label: 'Date',
                icon: Icons.event_outlined,
                value: DateDisplay.weekdayFull(transaction.transactionDate),
              ),
              const Divider(height: 1),
              DetailRow(
                label: 'Time',
                icon: Icons.schedule_outlined,
                value: DateDisplay.time(transaction.transactionDate),
              ),
              if (transaction.paymentMethod != null) ...[
                const Divider(height: 1),
                DetailRow(
                  label: 'Payment method',
                  icon: Icons.payment_outlined,
                  value: transaction.paymentMethod!.label,
                ),
              ],
              if (transaction.referenceNumber != null) ...[
                const Divider(height: 1),
                DetailRow(
                  label: 'Reference',
                  icon: Icons.tag_rounded,
                  value: transaction.referenceNumber,
                ),
              ],
              const Divider(height: 1),
              DetailRow(
                label: 'Source',
                icon: Icons.input_rounded,
                valueWidget: AppChipLabel(
                  label: transaction.source.label,
                  icon: transaction.isFromOcr
                      ? Icons.document_scanner_outlined
                      : null,
                ),
              ),
            ],
          ),
        ),

        if (transaction.description != null ||
            transaction.notes != null) ...[
          AppSpacing.gapLg,
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (transaction.description != null) ...[
                  Text('Description', style: context.text.labelMedium),
                  AppSpacing.gapXs,
                  Text(
                    transaction.description!,
                    style: context.text.bodyLarge,
                  ),
                ],
                if (transaction.description != null &&
                    transaction.notes != null)
                  AppSpacing.gapLg,
                if (transaction.notes != null) ...[
                  Text('Notes', style: context.text.labelMedium),
                  AppSpacing.gapXs,
                  Text(transaction.notes!, style: context.text.bodyMedium),
                ],
              ],
            ),
          ),
        ],

        if (transaction.splits.isNotEmpty) ...[
          AppSpacing.gapLg,
          _SplitsCard(transaction: transaction),
        ],

        if (transaction.documentId != null) ...[
          AppSpacing.gapLg,
          _AttachmentCard(transaction: transaction),
        ],

        AppSpacing.gapXxl,
        transaction.lendingId == null
            ? _ActionButtons(transaction: transaction)
            : _LendingLinkButton(lendingId: transaction.lendingId!),
        AppSpacing.gapXxl,

        Center(
          child: Text(
            'Added ${DateDisplay.timeAgo(transaction.createdAt)}',
            style: context.text.bodySmall,
          ),
        ),
        AppSpacing.gapXl,
      ],
    );
  }
}

class _AmountHeader extends StatelessWidget {
  const _AmountHeader({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IconBadge(
          icon: transaction.icon,
          color: transaction.type.isTransfer
              ? context.palette.transfer
              : (transaction.category?.color ?? context.palette.textSecondary),
          size: 60,
        ),
        AppSpacing.gapLg,
        MoneyText.transaction(
          transaction.amount,
          transactionType: transaction.type,
          size: MoneySize.hero,
        ),
        AppSpacing.gapSm,
        Text(
          transaction.title,
          style: context.text.titleMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _PendingBanner extends ConsumerWidget {
  const _PendingBanner({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      borderColor: context.palette.warning.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.pending_outlined,
                size: 18,
                color: context.palette.warning,
              ),
              AppSpacing.hGapSm,
              Text(
                'Draft transaction',
                style: context.text.titleSmall
                    ?.copyWith(color: context.palette.warning),
              ),
            ],
          ),
          AppSpacing.gapSm,
          Text(
            'This is saved as a draft, so it has not changed your account '
            'balance yet.',
            style: context.text.bodySmall,
          ),
          AppSpacing.gapMd,
          FilledButton(
            onPressed: () async {
              await AppFeedback.runWithProgress(
                context,
                progressMessage: 'Confirming…',
                successMessage: 'Transaction confirmed',
                action: () => ref
                    .read(transactionWriterProvider.notifier)
                    .confirmPending(transaction.id),
              );
            },
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Confirm transaction'),
          ),
        ],
      ),
    );
  }
}

class _SplitsCard extends StatelessWidget {
  const _SplitsCard({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: 'Split into ${transaction.splits.length} items',
      icon: Icons.call_split_rounded,
      action: TextButton(
        onPressed: () =>
            context.push(AppRoutes.transactionSplit(transaction.id)),
        child: const Text('Edit'),
      ),
      child: Column(
        children: [
          for (final split in transaction.splits)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                children: [
                  if (split.category != null) ...[
                    Icon(
                      split.category!.icon,
                      size: 16,
                      color: split.category!.color,
                    ),
                    AppSpacing.hGapSm,
                  ],
                  Expanded(
                    child: Text(
                      split.label,
                      style: context.text.bodyMedium
                          ?.copyWith(color: context.colors.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  MoneyText(split.amount, size: MoneySize.row),
                ],
              ),
            ),
          const Divider(height: 1),
          AppSpacing.gapMd,
          Row(
            children: [
              Expanded(
                child: Text('Total', style: context.text.titleSmall),
              ),
              MoneyText(transaction.splitTotal, size: MoneySize.row),
            ],
          ),
        ],
      ),
    );
  }
}

class _AttachmentCard extends ConsumerWidget {
  const _AttachmentCard({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document =
        ref.watch(documentByIdProvider(transaction.documentId!));

    return AppSectionCard(
      title: 'Attached document',
      icon: Icons.attach_file_rounded,
      child: document.view(
        (data) => Row(
          children: [
            IconBadge(icon: data.icon, color: context.colors.primary),
            AppSpacing.hGapLg,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.fileName,
                    style: context.text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${data.readableSize} · '
                    '${DateDisplay.relative(data.createdAt)}',
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () =>
                  context.push(AppRoutes.documentDetail(data.id)),
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              tooltip: 'View',
            ),
            IconButton(
              onPressed: () async {
                final confirmed = await AppFeedback.confirm(
                  context,
                  title: 'Remove attachment?',
                  message: 'The transaction stays; the document remains in '
                      'your documents list.',
                  confirmLabel: 'Remove',
                );
                if (!confirmed || !context.mounted) return;
                await AppFeedback.runWithProgress(
                  context,
                  successMessage: 'Attachment removed',
                  action: () => ref
                      .read(transactionWriterProvider.notifier)
                      .setAttachment(transaction.id, null),
                );
              },
              icon: const Icon(Icons.link_off_rounded, size: 20),
              tooltip: 'Remove attachment',
            ),
          ],
        ),
        loading: const LoadingView(compact: true),
        errorCompact: true,
      ),
    );
  }
}

/// Shown instead of Edit/Delete on a transaction a lending record produced.
///
/// Editing or deleting it here would change the account balance without
/// touching that record's outstanding total, leaving the two disagreeing —
/// so the only way to affect it is through the lending record itself.
class _LendingLinkButton extends StatelessWidget {
  const _LendingLinkButton({required this.lendingId});

  final String lendingId;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'This came from a lending record. Edit or settle it there instead.',
          style: context.text.bodySmall,
          textAlign: TextAlign.center,
        ),
        AppSpacing.gapMd,
        OutlinedButton.icon(
          onPressed: () => context.push(AppRoutes.lendingDetail(lendingId)),
          icon: const Icon(Icons.handshake_outlined, size: 18),
          label: const Text('View lending record'),
        ),
      ],
    );
  }
}

class _ActionButtons extends ConsumerWidget {
  const _ActionButtons({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () =>
                context.push(AppRoutes.transactionEdit(transaction.id)),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
          ),
        ),
        AppSpacing.hGapMd,
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _delete(context, ref),
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: context.palette.danger,
            ),
            label: Text(
              'Delete',
              style: TextStyle(color: context.palette.danger),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: context.palette.danger.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await AppFeedback.confirm(
      context,
      title: 'Delete transaction?',
      message: transaction.type.isTransfer
          ? 'Both sides of this transfer will be removed and both account '
              'balances adjusted.'
          : 'This transaction will be removed and your account balance '
              'adjusted.',
      confirmLabel: 'Delete',
      isDestructive: true,
      consequences: [
        if (transaction.splits.isNotEmpty)
          'Its ${transaction.splits.length} split items will be removed too.',
        if (transaction.hasAttachment)
          'The attached document stays in your documents.',
      ],
    );
    if (!confirmed || !context.mounted) return;

    final result = await AppFeedback.runWithProgress(
      context,
      progressMessage: 'Deleting…',
      successMessage: 'Transaction deleted',
      action: () async {
        await ref
            .read(transactionListControllerProvider.notifier)
            .delete(transaction);
        return true;
      },
    );

    if (result == true && context.mounted) context.pop();
  }
}

class _ActionsMenu extends ConsumerWidget {
  const _ActionsMenu({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (transaction.lendingId != null) {
      return IconButton(
        onPressed: () =>
            context.push(AppRoutes.lendingDetail(transaction.lendingId!)),
        icon: const Icon(Icons.handshake_outlined),
        tooltip: 'View lending record',
      );
    }

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (value) async {
        switch (value) {
          case 'duplicate':
            final copy = await AppFeedback.runWithProgress(
              context,
              progressMessage: 'Duplicating…',
              successMessage: 'Copied to today',
              action: () => ref
                  .read(transactionWriterProvider.notifier)
                  .duplicate(transaction),
            );
            if (copy != null && context.mounted) {
              context.pushReplacement(AppRoutes.transactionDetail(copy.id));
            }
          case 'split':
            context.push(AppRoutes.transactionSplit(transaction.id));
          case 'edit':
            context.push(AppRoutes.transactionEdit(transaction.id));
          case 'delete':
            final confirmed = await AppFeedback.confirm(
              context,
              title: 'Delete transaction?',
              message: transaction.type.isTransfer
                  ? 'Both sides of this transfer will be removed and both account balances adjusted.'
                  : 'This transaction will be removed and your account balance adjusted.',
              confirmLabel: 'Delete',
              isDestructive: true,
            );
            if (!confirmed || !context.mounted) return;
            final done = await AppFeedback.runWithProgress(
              context,
              progressMessage: 'Deleting…',
              successMessage: 'Transaction deleted',
              action: () async {
                await ref
                    .read(transactionListControllerProvider.notifier)
                    .delete(transaction);
                return true;
              },
            );
            if (done == true && context.mounted) context.pop();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Edit'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        // Transfers cannot be duplicated: a copy would need its own pair of
        // legs, which is what creating a new transfer does properly.
        if (!transaction.type.isTransfer)
          const PopupMenuItem(
            value: 'duplicate',
            child: ListTile(
              leading: Icon(Icons.copy_rounded),
              title: Text('Duplicate'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        if (!transaction.type.isTransfer)
          PopupMenuItem(
            value: 'split',
            child: ListTile(
              leading: const Icon(Icons.call_split_rounded),
              title: Text(
                transaction.isSplit ? 'Edit split' : 'Split transaction',
              ),
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
    );
  }
}
