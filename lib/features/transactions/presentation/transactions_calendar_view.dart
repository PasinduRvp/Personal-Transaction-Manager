import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/providers/transaction_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/transaction_tile.dart';

/// A monthly and daily calendar view for transactions.
class TransactionsCalendarView extends ConsumerStatefulWidget {
  const TransactionsCalendarView({super.key});

  @override
  ConsumerState<TransactionsCalendarView> createState() =>
      _TransactionsCalendarViewState();
}

class _TransactionsCalendarViewState
    extends ConsumerState<TransactionsCalendarView> {
  late DateTime _focusedMonth;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month);
    _selectedDate = DateTime(now.year, now.month, now.day);
  }

  void _previousMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    });
  }

  void _jumpToToday() {
    final now = DateTime.now();
    setState(() {
      _focusedMonth = DateTime(now.year, now.month);
      _selectedDate = DateTime(now.year, now.month, now.day);
    });
  }

  Future<void> _delete(Transaction transaction) async {
    final confirmed = await AppFeedback.confirm(
      context,
      title: 'Delete transaction?',
      message: transaction.type.isTransfer
          ? 'This will remove both sides of the transfer and adjust both account balances.'
          : 'This will remove the transaction and adjust your ${transaction.account?.name ?? 'account'} balance.',
      confirmLabel: 'Delete',
      isDestructive: true,
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
    final obscure = ref.watch(hideAmountsProvider);
    final currency = ref.watch(currencyProvider);

    final allItems = paged.valueOrNull?.items ?? [];

    // Filter transactions by focused month for high-level statistics
    final monthStart = AppDateUtils.startOfMonth(_focusedMonth);
    final monthEnd = AppDateUtils.endOfMonth(_focusedMonth);
    final monthItems = allItems
        .where((t) =>
            !t.transactionDate.isBefore(monthStart) &&
            !t.transactionDate.isAfter(monthEnd))
        .toList();

    // Map day to transactions
    final Map<int, List<Transaction>> dayMap = {};
    Money monthIncome = Money.zero(currency);
    Money monthExpense = Money.zero(currency);

    for (final item in monthItems) {
      final day = item.transactionDate.day;
      dayMap.putIfAbsent(day, () => []).add(item);

      if (item.type == TransactionType.income) {
        monthIncome = monthIncome + item.amount;
      } else if (item.type == TransactionType.expense) {
        monthExpense = monthExpense + item.amount;
      }
    }

    // Selected day transactions
    final selectedDayItems = allItems
        .where((t) =>
            AppDateUtils.isSameDay(t.transactionDate, _selectedDate))
        .toList();

    Money selectedDayTotal = Money.zero(currency);
    for (final t in selectedDayItems) {
      if (t.type == TransactionType.expense) {
        selectedDayTotal = selectedDayTotal + t.amount;
      }
    }

    return CustomScrollView(
      slivers: [
        // Month Navigation & Summary Header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.page,
              vertical: AppSpacing.sm,
            ),
            child: AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: _previousMonth,
                        icon: const Icon(Icons.chevron_left_rounded),
                        tooltip: 'Previous month',
                      ),
                      GestureDetector(
                        onTap: _jumpToToday,
                        child: Row(
                          children: [
                            Text(
                              DateFormat('MMMM yyyy').format(_focusedMonth),
                              style: context.text.titleLarge,
                            ),
                            if (!AppDateUtils.isSameDay(
                              _focusedMonth,
                              DateTime(DateTime.now().year, DateTime.now().month),
                            )) ...[
                              AppSpacing.hGapSm,
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.xs + 2,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: context.colors.primary.withValues(alpha: 0.15),
                                  borderRadius: AppRadius.pillAll,
                                ),
                                child: Text(
                                  'Today',
                                  style: context.text.labelSmall?.copyWith(
                                    color: context.colors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _nextMonth,
                        icon: const Icon(Icons.chevron_right_rounded),
                        tooltip: 'Next month',
                      ),
                    ],
                  ),
                  AppSpacing.gapMd,
                  const Divider(height: 1),
                  AppSpacing.gapSm,
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Text('Income', style: context.text.labelSmall),
                            const SizedBox(height: 2),
                            MoneyText(
                              monthIncome,
                              size: MoneySize.row,
                              color: context.palette.income,
                              obscured: obscure,
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 28, color: context.colors.outline),
                      Expanded(
                        child: Column(
                          children: [
                            Text('Expenses', style: context.text.labelSmall),
                            const SizedBox(height: 2),
                            MoneyText(
                              monthExpense,
                              size: MoneySize.row,
                              color: context.palette.expense,
                              obscured: obscure,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // Grid Calendar
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  // Days of week row
                  Row(
                    children: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                        .map(
                          (d) => Expanded(
                            child: Center(
                              child: Text(
                                d,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF4A7FA7),
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  AppSpacing.gapMd,
                  // Calendar Matrix
                  _CalendarGrid(
                    focusedMonth: _focusedMonth,
                    selectedDate: _selectedDate,
                    dayMap: dayMap,
                    currency: currency,
                    obscure: obscure,
                    onSelectDate: (d) => setState(() => _selectedDate = d),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Selected Day Header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.lg,
              AppSpacing.page,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    DateDisplay.sectionHeader(_selectedDate),
                    style: context.text.labelMedium?.copyWith(
                      color: context.palette.textSecondary,
                    ),
                  ),
                ),
                if (selectedDayItems.isNotEmpty)
                  Text(
                    'Spent: ${selectedDayTotal.formatCompact()}',
                    style: context.text.labelMedium?.copyWith(
                      color: context.palette.expense,
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Selected Day Transactions List
        if (selectedDayItems.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: EmptyState(
                icon: Icons.calendar_today_outlined,
                title: 'No transactions on this date',
                message: 'Tap + button to add a transaction for ${DateDisplay.relative(_selectedDate)}.',
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: selectedDayItems.length,
            itemBuilder: (context, index) {
              final transaction = selectedDayItems[index];
              return SwipeableTransactionTile(
                key: ValueKey(transaction.id),
                transaction: transaction,
                obscureAmount: obscure,
                onTap: () =>
                    context.push(AppRoutes.transactionDetail(transaction.id)),
                onEdit: () =>
                    context.push(AppRoutes.transactionEdit(transaction.id)),
                onDelete: () => _delete(transaction),
              );
            },
          ),

        const SliverToBoxAdapter(
          child: SizedBox(height: AppSpacing.bottomNavClearance),
        ),
      ],
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.focusedMonth,
    required this.selectedDate,
    required this.dayMap,
    required this.currency,
    required this.obscure,
    required this.onSelectDate,
  });

  final DateTime focusedMonth;
  final DateTime selectedDate;
  final Map<int, List<Transaction>> dayMap;
  final String currency;
  final bool obscure;
  final ValueChanged<DateTime> onSelectDate;

  @override
  Widget build(BuildContext context) {
    final firstDayOfMonth = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final daysInMonth = AppDateUtils.daysInMonth(focusedMonth);

    // Monday is weekday 1
    final leadingPadding = firstDayOfMonth.weekday - 1;
    final totalCells = ((leadingPadding + daysInMonth) / 7).ceil() * 7;

    final today = DateTime.now();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: totalCells,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 1.0,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemBuilder: (context, index) {
        final dayNumber = index - leadingPadding + 1;
        if (dayNumber < 1 || dayNumber > daysInMonth) {
          return const SizedBox.shrink();
        }

        final cellDate = DateTime(focusedMonth.year, focusedMonth.month, dayNumber);
        final isSelected = AppDateUtils.isSameDay(cellDate, selectedDate);
        final isToday = AppDateUtils.isSameDay(cellDate, today);
        final items = dayMap[dayNumber] ?? [];

        final hasExpense =
            items.any((t) => t.type == TransactionType.expense);
        final hasIncome = items.any((t) => t.type == TransactionType.income);

        return InkWell(
          onTap: () => onSelectDate(cellDate),
          borderRadius: AppRadius.mdAll,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: AppRadius.mdAll,
              color: isSelected
                  ? context.colors.primary
                  : isToday
                      ? context.colors.primary.withValues(alpha: 0.18)
                      : items.isNotEmpty
                          ? context.colors.surfaceContainerHigh.withValues(alpha: 0.5)
                          : Colors.transparent,
              border: isToday && !isSelected
                  ? Border.all(color: context.colors.primary, width: 1.5)
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$dayNumber',
                  style: context.text.titleSmall?.copyWith(
                    fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? context.colors.onPrimary
                        : context.colors.onSurface,
                  ),
                ),
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (hasExpense)
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected
                                ? Colors.white
                                : context.palette.expense,
                          ),
                        ),
                      if (hasIncome)
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected
                                ? Colors.white70
                                : context.palette.income,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
