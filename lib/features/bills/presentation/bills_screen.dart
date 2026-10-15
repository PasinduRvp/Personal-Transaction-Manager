import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../shared/models/account.dart';
import '../../../shared/models/bill.dart';
import '../../../shared/providers/account_providers.dart';
import '../../../shared/providers/planning_providers.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/pickers.dart';
import '../../../shared/widgets/state_views.dart';

/// Bills, grouped by urgency.
///
/// Overdue first, then due today, tomorrow, this week, and upcoming — the order
/// someone actually cares about when they open this screen.
class BillsScreen extends ConsumerWidget {
  const BillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bills = ref.watch(billsControllerProvider);
    final buckets = ref.watch(billBucketsProvider);
    final outstanding = ref.watch(outstandingBillsTotalProvider);
    final obscure = ref.watch(hideAmountsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bills'),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.billAdd),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add bill',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(billsControllerProvider.notifier).refresh(),
        child: bills.view(
          (data) {
            if (data.isEmpty) {
              return EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No bills yet',
                message: 'Add your recurring bills and Finora will remind you '
                    'before each one is due.',
                actionLabel: 'Add bill',
                onAction: () => context.push(AppRoutes.billAdd),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.lg,
                AppSpacing.page,
                AppSpacing.xxl,
              ),
              children: [
                if (!outstanding.isZero)
                  AppCard(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Still to pay', style: context.text.labelMedium),
                        AppSpacing.gapSm,
                        MoneyText(
                          outstanding,
                          size: MoneySize.hero,
                          obscured: obscure,
                        ),
                        AppSpacing.gapSm,
                        Text(
                          '${data.where((b) => !b.isPaid && !b.isCancelled).length} '
                          'unpaid bill'
                          '${data.where((b) => !b.isPaid && !b.isCancelled).length == 1 ? '' : 's'}',
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                AppSpacing.gapXl,

                for (final entry in buckets.entries) ...[
                  _BucketHeader(bucket: entry.key, count: entry.value.length),
                  AppSpacing.gapMd,
                  AppCard(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Column(
                      children: [
                        for (var i = 0; i < entry.value.length; i++) ...[
                          if (i > 0)
                            const Divider(height: 1, indent: AppSpacing.lg),
                          _BillRow(bill: entry.value[i], obscured: obscure),
                        ],
                      ],
                    ),
                  ),
                  AppSpacing.gapXl,
                ],

                OutlinedButton.icon(
                  onPressed: () => context.push(AppRoutes.billAdd),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add bill'),
                ),
              ],
            );
          },
          loading: const _BillsSkeleton(),
          onRetry: () => ref.read(billsControllerProvider.notifier).refresh(),
        ),
      ),
    );
  }
}

class _BucketHeader extends StatelessWidget {
  const _BucketHeader({required this.bucket, required this.count});

  final BillBucket bucket;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = switch (bucket) {
      BillBucket.overdue => context.palette.danger,
      BillBucket.dueToday => context.palette.warning,
      BillBucket.dueTomorrow => context.palette.warning,
      BillBucket.dueThisWeek => context.palette.info,
      BillBucket.paid => context.palette.income,
      _ => context.palette.textSecondary,
    };

    return Row(
      children: [
        Text(
          bucket.label.toUpperCase(),
          style: context.text.labelSmall?.copyWith(color: color),
        ),
        AppSpacing.hGapSm,
        Text(
          '($count)',
          style: context.text.labelSmall
              ?.copyWith(color: context.palette.textTertiary),
        ),
      ],
    );
  }
}

class _BillRow extends ConsumerWidget {
  const _BillRow({required this.bill, this.obscured = false});

  final Bill bill;
  final bool obscured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUrgent = bill.isOverdue || bill.isDueToday;

    return ListTile(
      onTap: () => context.push(AppRoutes.billEdit(bill.id)),
      leading: IconBadge(
        icon: bill.category?.icon ?? Icons.receipt_long_outlined,
        color: bill.isPaid
            ? context.palette.income
            : (bill.category?.color ?? context.palette.textSecondary),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              bill.name,
              style: context.text.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (bill.isRecurring)
            Icon(
              Icons.repeat_rounded,
              size: 13,
              color: context.palette.textTertiary,
            ),
        ],
      ),
      subtitle: Text(
        bill.isPaid
            ? 'Paid ${bill.lastPaidOn == null ? '' : DateDisplay.relative(bill.lastPaidOn!)}'
            : DateDisplay.dueDescription(bill.dueDate),
        style: context.text.bodySmall?.copyWith(
          color: isUrgent ? context.palette.danger : null,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MoneyText(bill.amount, size: MoneySize.row, obscured: obscured),
          if (!bill.isPaid && !bill.isCancelled) ...[
            AppSpacing.hGapSm,
            TextButton(
              onPressed: () => MarkPaidSheet.show(context, bill: bill),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Pay'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Records a bill payment.
///
/// Requires an account, because marking a bill paid also creates the expense
/// transaction — the money has to come from somewhere for the balances to stay
/// truthful.
class MarkPaidSheet extends ConsumerStatefulWidget {
  const MarkPaidSheet({super.key, required this.bill});

  final Bill bill;

  static Future<void> show(BuildContext context, {required Bill bill}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: MarkPaidSheet(bill: bill),
      ),
    );
  }

  @override
  ConsumerState<MarkPaidSheet> createState() => _MarkPaidSheetState();
}

class _MarkPaidSheetState extends ConsumerState<MarkPaidSheet> {
  late final TextEditingController _amountController;
  Account? _account;
  DateTime _paidOn = DateTime.now();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.bill.amount.toEditableString(),
    );
    // Default to the bill's own account, then the user's default.
    _account = ref.read(accountByIdProvider(widget.bill.accountId)) ??
        ref.read(defaultAccountProvider);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final account = _account;
    if (account == null) {
      AppFeedback.showValidation(
        context,
        'Choose the account this was paid from.',
      );
      return;
    }

    final amount = Money.tryParse(_amountController.text, account.currency);
    if (amount == null || amount.isZero) {
      AppFeedback.showValidation(context, 'Enter the amount paid.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref.read(billsControllerProvider.notifier).markPaid(
            billId: widget.bill.id,
            accountId: account.id,
            paidOn: _paidOn,
            amount: amount,
          );

      if (!mounted) return;
      Navigator.of(context).pop();
      AppFeedback.showSuccess(
        context,
        widget.bill.isRecurring
            ? 'Paid — next due date set'
            : '${widget.bill.name} marked as paid',
      );
    } on Object catch (error) {
      if (mounted) AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(activeAccountsProvider);
    final currency = _account?.currency ?? widget.bill.amount.currency;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pay ${widget.bill.name}', style: context.text.titleLarge),
            AppSpacing.gapSm,
            Text(
              'This records an expense transaction so your balance stays '
              'accurate.',
              style: context.text.bodySmall,
            ),
            AppSpacing.gapXl,

            AmountField(
              controller: _amountController,
              currency: currency,
              label: 'Amount paid',
            ),
            AppSpacing.gapLg,

            PickerField(
              label: 'Paid from',
              isRequired: true,
              value: _account?.name,
              leading: _account == null
                  ? null
                  : IconBadge(
                      icon: _account!.icon,
                      color: _account!.color,
                      size: 24,
                      iconSize: 14,
                    ),
              onTap: () async {
                final picked = await AccountPicker.show(
                  context,
                  accounts: accounts,
                  selectedId: _account?.id,
                );
                if (picked != null) setState(() => _account = picked);
              },
            ),
            AppSpacing.gapLg,

            PickerField(
              label: 'Paid on',
              value: DateDisplay.dayMonthYear(_paidOn),
              leading: const Icon(Icons.event_outlined, size: 20),
              onTap: () async {
                final picked = await DateTimePickers.pickTransactionDate(
                  context,
                  initial: _paidOn,
                );
                if (picked != null) setState(() => _paidOn = picked);
              },
            ),

            if (widget.bill.isRecurring) ...[
              AppSpacing.gapLg,
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
                      Icons.repeat_rounded,
                      size: 18,
                      color: context.palette.info,
                    ),
                    AppSpacing.hGapMd,
                    Expanded(
                      child: Text(
                        'This bill repeats, so its due date moves forward to '
                        'the next period.',
                        style: context.text.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            AppSpacing.gapXxl,
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Record payment'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BillsSkeleton extends StatelessWidget {
  const _BillsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: const [
        CardSkeleton(height: 130),
        SizedBox(height: AppSpacing.xl),
        Skeleton(width: 80, height: 12),
        SizedBox(height: AppSpacing.md),
        CardSkeleton(height: 150),
        SizedBox(height: AppSpacing.xl),
        Skeleton(width: 100, height: 12),
        SizedBox(height: AppSpacing.md),
        CardSkeleton(height: 90),
      ],
    );
  }
}
