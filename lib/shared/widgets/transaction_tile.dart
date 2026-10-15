import 'package:flutter/material.dart';

import '../../core/extensions/context_extensions.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/money.dart';
import '../models/transaction.dart';
import 'app_card.dart';
import 'money_text.dart';

/// One row of the transaction history.
///
/// Dense on purpose: the point of this list is scanning many rows quickly, so
/// each one shows the category icon, what it was, which account, and how much —
/// and nothing else.
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    this.onTap,
    this.showAccount = true,
    this.showTime = true,
    this.obscureAmount = false,
    this.dense = false,
  });

  final Transaction transaction;
  final VoidCallback? onTap;
  final bool showAccount;
  final bool showTime;
  final bool obscureAmount;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final category = transaction.category;
    final iconColor = transaction.type.isTransfer
        ? context.palette.transfer
        : (category?.color ?? context.palette.textSecondary);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.page,
          vertical: dense ? AppSpacing.sm : AppSpacing.md,
        ),
        child: Row(
          children: [
            IconBadge(
              icon: transaction.icon,
              color: iconColor,
              size: dense ? 36 : 42,
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          transaction.title,
                          style: context.text.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // A pending row is a draft; saying so prevents the user
                      // wondering why their balance has not moved.
                      if (transaction.isPending) ...[
                        AppSpacing.hGapSm,
                        AppChipLabel(
                          label: 'Pending',
                          color: context.palette.warning,
                          dense: true,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(context),
                    style: context.text.bodySmall,
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
                MoneyText.transaction(
                  transaction.amount,
                  transactionType: transaction.type,
                  obscured: obscureAmount,
                ),
                if (transaction.hasAttachment || transaction.isFromOcr) ...[
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (transaction.isFromOcr)
                        Icon(
                          Icons.document_scanner_outlined,
                          size: 12,
                          color: context.palette.textTertiary,
                        ),
                      if (transaction.hasAttachment) ...[
                        if (transaction.isFromOcr) const SizedBox(width: 3),
                        Icon(
                          Icons.attach_file_rounded,
                          size: 12,
                          color: context.palette.textTertiary,
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(BuildContext context) {
    final parts = <String>[];

    final subtitle = transaction.subtitle;
    if (subtitle != null && subtitle.isNotEmpty) parts.add(subtitle);

    if (showAccount && transaction.account != null) {
      parts.add(transaction.account!.name);
    }

    if (showTime) parts.add(DateDisplay.time(transaction.transactionDate));

    return parts.isEmpty ? transaction.type.label : parts.join(' · ');
  }
}

/// A transaction tile with swipe actions.
///
/// Delete requires confirmation rather than happening on the swipe: an
/// accidental swipe should not be able to remove a financial record, and an
/// undo snackbar is not a substitute when the row also moved an account balance.
class SwipeableTransactionTile extends StatelessWidget {
  const SwipeableTransactionTile({
    super.key,
    required this.transaction,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onDuplicate,
    this.obscureAmount = false,
  });

  final Transaction transaction;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final Future<void> Function()? onDelete;
  final VoidCallback? onDuplicate;
  final bool obscureAmount;

  @override
  Widget build(BuildContext context) {
    if (onDelete == null && onEdit == null) {
      return TransactionTile(
        transaction: transaction,
        onTap: onTap,
        obscureAmount: obscureAmount,
      );
    }

    return Dismissible(
      key: ValueKey('swipe-${transaction.id}'),
      direction: DismissDirection.horizontal,
      background: _SwipeBackground(
        alignment: Alignment.centerLeft,
        color: context.palette.info,
        icon: Icons.edit_outlined,
        label: 'Edit',
      ),
      secondaryBackground: _SwipeBackground(
        alignment: Alignment.centerRight,
        color: context.palette.danger,
        icon: Icons.delete_outline_rounded,
        label: 'Delete',
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onEdit?.call();
          // Never actually dismiss for an edit — the row still exists.
          return false;
        }
        if (onDelete == null) return false;
        await onDelete!();
        // The list is refreshed by the controller, so the widget must not remove
        // itself as well; doing both double-removes and throws.
        return false;
      },
      child: TransactionTile(
        transaction: transaction,
        onTap: onTap,
        obscureAmount: obscureAmount,
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color.withValues(alpha: context.isDark ? 0.24 : 0.14),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          AppSpacing.hGapSm,
          Text(
            label,
            style: context.text.labelLarge?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// The date header above a day's transactions, with the day's net movement.
class TransactionDayHeader extends StatelessWidget {
  const TransactionDayHeader({
    super.key,
    required this.group,
    required this.currency,
    this.obscureAmount = false,
  });

  final TransactionDayGroup group;
  final String currency;
  final bool obscureAmount;

  @override
  Widget build(BuildContext context) {
    final net = group.net(currency);

    return Container(
      color: context.colors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              DateDisplay.sectionHeader(group.date),
              style: context.text.labelSmall
                  ?.copyWith(color: context.palette.textSecondary),
            ),
          ),
          if (!net.isZero)
            MoneyText(
              net,
              size: MoneySize.small,
              obscured: obscureAmount,
              // A day's net is neutral information, not an income or expense
              // event, so it is not signed with a plus.
              color: net.isNegative
                  ? context.palette.textSecondary
                  : context.palette.income,
            ),
        ],
      ),
    );
  }
}

/// A compact summary row used on the account detail screen.
class TransactionMiniTile extends StatelessWidget {
  const TransactionMiniTile({
    super.key,
    required this.transaction,
    this.onTap,
  });

  final Transaction transaction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      leading: IconBadge(
        icon: transaction.icon,
        color: transaction.category?.color ?? context.palette.textSecondary,
        size: 34,
      ),
      title: Text(
        transaction.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.text.titleSmall,
      ),
      subtitle: Text(
        DateDisplay.relative(transaction.transactionDate),
        style: context.text.bodySmall,
      ),
      trailing: MoneyText.transaction(
        transaction.amount,
        transactionType: transaction.type,
      ),
    );
  }
}

/// A banner warning that split lines do not add up to the parent amount.
class SplitMismatchBanner extends StatelessWidget {
  const SplitMismatchBanner({
    super.key,
    required this.total,
    required this.splitTotal,
  });

  final Money total;
  final Money splitTotal;

  @override
  Widget build(BuildContext context) {
    final difference = total - splitTotal;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.palette.warning
            .withValues(alpha: context.isDark ? 0.18 : 0.1),
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: context.palette.warning,
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Text(
              difference.isPositive
                  ? 'Splits are ${difference.format()} under the '
                      '${total.format()} total'
                  : 'Splits exceed the total by ${difference.abs.format()}',
              style: context.text.bodySmall
                  ?.copyWith(color: context.palette.warning),
            ),
          ),
        ],
      ),
    );
  }
}
