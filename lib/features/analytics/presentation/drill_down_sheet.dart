import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/money.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/providers/analytics_providers.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/transaction_tile.dart';

/// The transactions behind a chart element.
///
/// A sheet rather than a new screen, so the user keeps their place in the chart
/// they were reading and can close it with a swipe.
class DrillDownSheet extends ConsumerWidget {
  const DrillDownSheet({super.key, required this.drill});

  final DrillDown drill;

  static Future<void> show(BuildContext context, {required DrillDown drill}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (context) => DrillDownSheet(drill: drill),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactions = ref.watch(drillDownProvider(drill));
    final currency = ref.watch(currencyProvider);
    final filter = ref.watch(analyticsFilterProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                drill.label ?? 'Transactions',
                style: context.text.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(
                (drill.range ?? filter.range).label,
                style: context.text.bodySmall,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: transactions.view(
            (data) => _DrillList(
              transactions: _filtered(data),
              currency: currency,
            ),
            loading: const TransactionSkeleton(count: 5),
            onRetry: () => ref.invalidate(drillDownProvider(drill)),
          ),
        ),
      ],
    );
  }

  /// Merchant filtering happens here rather than in SQL: the drill-down query
  /// already narrows by type, period and category, and matching a merchant name
  /// is a display-level concern that should not need another round trip.
  List<Transaction> _filtered(List<Transaction> transactions) {
    final merchant = drill.merchant;
    if (merchant == null) return transactions;
    final needle = merchant.toLowerCase().trim();
    return transactions
        .where((t) => (t.merchant ?? '').toLowerCase().trim() == needle)
        .toList();
  }
}

class _DrillList extends StatelessWidget {
  const _DrillList({required this.transactions, required this.currency});

  final List<Transaction> transactions;
  final String currency;

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No transactions',
        message: 'Nothing matched this selection.',
        compact: true,
      );
    }

    var total = Money.zero(currency);
    for (final transaction in transactions) {
      if (transaction.amount.currency == currency) {
        total += transaction.amount;
      }
    }

    return ListView(
      shrinkWrap: true,
      children: [
        Container(
          color: context.colors.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.page,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${transactions.length} '
                  'transaction${transactions.length == 1 ? '' : 's'}',
                  style: context.text.labelMedium,
                ),
              ),
              MoneyText(total, size: MoneySize.row),
            ],
          ),
        ),
        for (final transaction in transactions)
          TransactionTile(
            transaction: transaction,
            onTap: () {
              Navigator.of(context).pop();
              context.push(AppRoutes.transactionDetail(transaction.id));
            },
          ),
        AppSpacing.gapXl,
      ],
    );
  }
}
