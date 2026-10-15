import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/models/transaction_query.dart';
import '../../../shared/repositories/transaction_repository.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/providers/transaction_providers.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/transaction_tile.dart';
import 'transaction_filter_sheet.dart';
import 'transactions_calendar_view.dart';

/// The transaction history.
///
/// A single scrollable list with a sticky search bar, grouped by day. Filters and
/// sorting live in a sheet rather than on the screen, because the common case is
/// scanning recent spending, not configuring a query.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _isCalendarView = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Prefetch before the user reaches the bottom, so the next page is usually
    // already there rather than appearing after a visible pause.
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      ref.read(transactionListControllerProvider.notifier).loadMore();
    }
  }

  void _onSearchChanged(String value) {
    // Debounced: firing a query on every keystroke would issue a request per
    // letter and make the list flicker as results race each other.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(transactionQueryProvider.notifier).setSearch(value);
    });
  }

  Future<void> _delete(Transaction transaction) async {
    final confirmed = await AppFeedback.confirm(
      context,
      title: 'Delete transaction?',
      message: transaction.type.isTransfer
          ? 'This will remove both sides of the transfer and adjust both '
              'account balances.'
          : 'This will remove the transaction and adjust your '
              '${transaction.account?.name ?? 'account'} balance.',
      confirmLabel: 'Delete',
      isDestructive: true,
      consequences: [
        if (transaction.hasAttachment)
          'The attached receipt stays in your documents.',
      ],
    );
    if (!confirmed) return;

    try {
      await ref
          .read(transactionListControllerProvider.notifier)
          .delete(transaction);
      if (mounted) AppFeedback.showSuccess(context, 'Transaction deleted');
    } on Object catch (error) {
      if (mounted) AppFeedback.showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paged = ref.watch(transactionListControllerProvider);
    final query = ref.watch(transactionQueryProvider);
    final groups = ref.watch(groupedTransactionsProvider);
    final obscure = ref.watch(hideAmountsProvider);
    final currency = ref.watch(currencyProvider);
    final totalCount = ref.watch(transactionCountProvider).valueOrNull;

    // A load-more failure is surfaced without discarding the pages already
    // loaded, so a flaky connection does not reset the user's scroll position.
    ref.listen(transactionListErrorProvider, (previous, next) {
      if (next != null && next != previous) {
        AppFeedback.showError(context, next);
      }
    });

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _SearchBar(
              controller: _searchController,
              onChanged: _onSearchChanged,
              onClear: () {
                _searchController.clear();
                ref.read(transactionQueryProvider.notifier).setSearch(null);
              },
              filterCount: query.activeFilterCount,
              isCalendarView: _isCalendarView,
              onViewModeToggle: () =>
                  setState(() => _isCalendarView = !_isCalendarView),
              onFilterTap: () => TransactionFilterSheet.show(context),
              onSortTap: () => _showSortSheet(context),
            ),
            if (!_isCalendarView && !query.isEmpty)
              _ActiveFilterChips(
                query: query,
                resultCount: totalCount,
                onClear: () {
                  _searchController.clear();
                  ref.read(transactionQueryProvider.notifier).reset();
                },
              ),
            Expanded(
              child: _isCalendarView
                  ? const TransactionsCalendarView()
                  : RefreshIndicator(
                      onRefresh: () => ref
                          .read(transactionListControllerProvider.notifier)
                          .refresh(),
                      child: paged.view(
                        (data) => data.isEmpty
                            ? _EmptyList(hasFilters: !query.isEmpty)
                            : _TransactionList(
                                groups: groups,
                                currency: currency,
                                obscured: obscure,
                                isLoadingMore: data.isLoadingMore,
                                hasMore: data.hasMore,
                                scrollController: _scrollController,
                                onDelete: _delete,
                              ),
                        loading: const TransactionSkeleton(count: 8),
                        onRetry: () => ref
                            .read(transactionListControllerProvider.notifier)
                            .refresh(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSortSheet(BuildContext context) async {
    final current = ref.read(transactionQueryProvider).sort;
    final picked = await AppFeedback.showSheet<TransactionSort>(
      context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.sm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Sort by', style: context.text.titleLarge),
              ),
            ),
            const Divider(height: 1),
            for (final sort in TransactionSort.values)
              ListTile(
                title: Text(sort.label, style: context.text.titleSmall),
                trailing: sort == current
                    ? Icon(Icons.check_rounded, color: context.colors.primary)
                    : null,
                onTap: () => Navigator.of(context).pop(sort),
              ),
          ],
        ),
      ),
    );

    if (picked != null) {
      ref.read(transactionQueryProvider.notifier).setSort(picked);
    }
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.filterCount,
    required this.isCalendarView,
    required this.onViewModeToggle,
    required this.onFilterTap,
    required this.onSortTap,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final int filterCount;
  final bool isCalendarView;
  final VoidCallback onViewModeToggle;
  final VoidCallback onFilterTap;
  final VoidCallback onSortTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.md,
        AppSpacing.page,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search merchant, note or amount',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: onClear,
                          tooltip: 'Clear',
                        ),
                ),
              ),
            ),
          ),
          AppSpacing.hGapSm,
          _IconAction(
            icon: isCalendarView
                ? Icons.view_agenda_outlined
                : Icons.calendar_month_outlined,
            onTap: onViewModeToggle,
            tooltip: isCalendarView ? 'List view' : 'Calendar view',
          ),
          AppSpacing.hGapXs,
          _IconAction(
            icon: Icons.tune_rounded,
            onTap: onFilterTap,
            badgeCount: filterCount,
            tooltip: 'Filters',
          ),
          AppSpacing.hGapXs,
          _IconAction(
            icon: Icons.swap_vert_rounded,
            onTap: onSortTap,
            tooltip: 'Sort',
          ),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.badgeCount = 0,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.mdAll,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: context.colors.outline),
            color: badgeCount > 0
                ? context.colors.primaryContainer
                : context.colors.surface,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: badgeCount > 0
                    ? context.colors.primary
                    : context.palette.textSecondary,
              ),
              if (badgeCount > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: context.colors.primary,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$badgeCount',
                      style: context.text.labelSmall?.copyWith(
                        color: context.colors.onPrimary,
                        fontSize: 9,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveFilterChips extends ConsumerWidget {
  const _ActiveFilterChips({
    required this.query,
    required this.onClear,
    this.resultCount,
  });

  final TransactionQuery query;
  final VoidCallback onClear;
  final TransactionCountResult? resultCount;

  /// `12 results`, or `about 12 results` when some filtering happened on the
  /// client and the count is therefore an upper bound.
  static String _countLabel(TransactionCountResult? count) {
    if (count == null) return 'Filtered results';
    final plural = count.count == 1 ? '' : 's';
    return count.isExact
        ? '${count.count} result$plural'
        : 'about ${count.count} result$plural';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = query.chipLabels;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (labels.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: AppSpacing.pageInsets,
              child: Row(
                children: [
                  for (final label in labels)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: Chip(
                        label: Text(label),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.sm,
              AppSpacing.page,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _countLabel(resultCount),
                    style: context.text.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: onClear,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Clear all'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionList extends StatelessWidget {
  const _TransactionList({
    required this.groups,
    required this.currency,
    required this.obscured,
    required this.isLoadingMore,
    required this.hasMore,
    required this.scrollController,
    required this.onDelete,
  });

  final List<TransactionDayGroup> groups;
  final String currency;
  final bool obscured;
  final bool isLoadingMore;
  final bool hasMore;
  final ScrollController scrollController;
  final Future<void> Function(Transaction) onDelete;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        for (final group in groups) ...[
          SliverToBoxAdapter(
            child: TransactionDayHeader(
              group: group,
              currency: currency,
              obscureAmount: obscured,
            ),
          ),
          SliverList.builder(
            itemCount: group.transactions.length,
            itemBuilder: (context, index) {
              final transaction = group.transactions[index];
              return SwipeableTransactionTile(
                key: ValueKey(transaction.id),
                transaction: transaction,
                obscureAmount: obscured,
                onTap: () =>
                    context.push(AppRoutes.transactionDetail(transaction.id)),
                onEdit: () =>
                    context.push(AppRoutes.transactionEdit(transaction.id)),
                onDelete: () => onDelete(transaction),
              );
            },
          ),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.xl,
              bottom: AppSpacing.bottomNavClearance,
            ),
            child: Center(
              child: isLoadingMore
                  ? const LoadingView(compact: true)
                  : hasMore
                      ? const SizedBox.shrink()
                      : Text(
                          "That's everything",
                          style: context.text.bodySmall,
                        ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.hasFilters});

  final bool hasFilters;

  @override
  Widget build(BuildContext context) {
    if (hasFilters) {
      return const EmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: 'No matching transactions',
        message: 'Try widening your search or clearing some filters.',
      );
    }

    return EmptyState(
      icon: Icons.receipt_long_outlined,
      title: 'No transactions yet',
      message: 'Start tracking your finances by adding your first transaction.',
      actionLabel: 'Add transaction',
      onAction: () => context.push(AppRoutes.transactionAdd),
      secondaryActionLabel: 'Import a receipt instead',
      onSecondaryAction: () => context.push(AppRoutes.importDocument),
    );
  }
}
