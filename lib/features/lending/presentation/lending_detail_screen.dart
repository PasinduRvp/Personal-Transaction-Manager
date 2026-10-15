import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/models/lending.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/providers/account_providers.dart';
import '../../../shared/providers/planning_providers.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/pickers.dart';
import '../../../shared/widgets/state_views.dart';

/// One lending record: progress, repayment history, and the actions on it.
class LendingDetailScreen extends ConsumerWidget {
  const LendingDetailScreen({super.key, required this.lendingId});

  final String lendingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lending = ref.watch(lendingByIdProvider(lendingId));
    final lendings = ref.watch(lendingControllerProvider);

    if (lending == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lending')),
        body: lendings.view(
          (_) => const EmptyState(
            icon: Icons.search_off_rounded,
            title: 'Not found',
            message: 'It may have been deleted.',
          ),
          loading: const LoadingView(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(lending.personName),
        actions: [_LendingMenu(lending: lending)],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(lendingControllerProvider.notifier).refresh(),
        child: _Body(lending: lending),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.lending});

  final LendingRecord lending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(lendingHistoryProvider(lending.id));
    final obscure = ref.watch(hideAmountsProvider);
    final account = ref.watch(accountByIdProvider(lending.accountId));

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              IconBadge(icon: lending.icon, color: lending.color, size: 60),
              AppSpacing.gapLg,
              Text(
                lending.kind.isReceivable ? 'Owed to you' : 'You owe',
                style: context.text.labelMedium,
              ),
              AppSpacing.gapXs,
              MoneyText(
                lending.outstanding,
                size: MoneySize.hero,
                obscured: obscure,
                color: lending.isSettled
                    ? null
                    : lending.kind.isReceivable
                        ? context.palette.income
                        : context.palette.danger,
              ),
              AppSpacing.gapLg,
              ProgressMeter(
                fraction: lending.progressFraction,
                color: lending.color,
                height: 12,
              ),
              AppSpacing.gapMd,
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'of ${lending.principal.format()}',
                    style: context.text.titleSmall,
                  ),
                  Text(
                    lending.isSettled
                        ? 'Fully settled'
                        : '${lending.repaidAmount.format()} repaid',
                    style: context.text.bodyMedium?.copyWith(
                      color: lending.isSettled ? context.palette.income : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        AppSpacing.gapLg,

        if (!lending.isSettled)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => RepaymentSheet.show(context, lending: lending),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: Text(
                lending.kind.isReceivable
                    ? 'Record repayment received'
                    : 'Record repayment made',
              ),
            ),
          ),
        AppSpacing.gapLg,

        AppCard(
          child: Column(
            children: [
              DetailRow(
                label: 'Principal',
                icon: Icons.flag_outlined,
                valueWidget: MoneyText(
                  lending.principal,
                  size: MoneySize.row,
                  obscured: obscure,
                ),
              ),
              const Divider(height: 1),
              DetailRow(
                label: 'Account',
                icon: Icons.account_balance_wallet_outlined,
                value: account?.name ?? 'Account removed',
                onTap: account == null
                    ? null
                    : () =>
                        context.push(AppRoutes.accountDetail(lending.accountId)),
              ),
              if (lending.dueDate != null) ...[
                const Divider(height: 1),
                DetailRow(
                  label: 'Expected back by',
                  icon: Icons.event_available_outlined,
                  value: DateDisplay.dayMonthYear(lending.dueDate!),
                ),
              ],
            ],
          ),
        ),

        if (lending.notes != null) ...[
          AppSpacing.gapLg,
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notes', style: context.text.labelMedium),
                AppSpacing.gapXs,
                Text(lending.notes!, style: context.text.bodyMedium),
              ],
            ),
          ),
        ],

        AppSpacing.gapXl,
        Text('History', style: context.text.titleMedium),
        AppSpacing.gapMd,
        history.view(
          (data) => data.isEmpty
              ? const EmptyState(
                  icon: Icons.history_rounded,
                  title: 'No history',
                  message: 'Transactions for this record will appear here.',
                  compact: true,
                )
              : AppCard(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Column(
                    children: [
                      for (var i = 0; i < data.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, indent: AppSpacing.lg),
                        _HistoryRow(transaction: data[i], lending: lending),
                      ],
                    ],
                  ),
                ),
          loading: const CardSkeleton(height: 140),
          onRetry: () => ref.invalidate(lendingHistoryProvider(lending.id)),
        ),
        AppSpacing.gapXxl,
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.transaction, required this.lending});

  final Transaction transaction;
  final LendingRecord lending;

  @override
  Widget build(BuildContext context) {
    final isPrincipal = transaction.amount == lending.principal &&
        transaction.transferDirection ==
            (lending.kind.isReceivable
                ? TransferDirection.out
                : TransferDirection.incoming) &&
        lending.repaidAmount.isZero;
    final isInflow = transaction.transferDirection == TransferDirection.incoming;

    return ListTile(
      leading: IconBadge(
        icon: isInflow ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
        color: isInflow ? context.palette.income : context.palette.expense,
        size: 34,
      ),
      title: Text(
        isPrincipal
            ? (lending.kind.isReceivable ? 'Lent' : 'Borrowed')
            : 'Repayment',
        style: context.text.titleSmall,
      ),
      subtitle: Text(
        DateDisplay.relative(transaction.transactionDate),
        style: context.text.bodySmall,
      ),
      trailing: MoneyText(
        transaction.amount,
        size: MoneySize.row,
        color: isInflow ? context.palette.income : context.palette.expense,
      ),
    );
  }
}

/// Records a repayment against a lending record.
class RepaymentSheet extends ConsumerStatefulWidget {
  const RepaymentSheet({super.key, required this.lending});

  final LendingRecord lending;

  static Future<void> show(
    BuildContext context, {
    required LendingRecord lending,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: RepaymentSheet(lending: lending),
      ),
    );
  }

  @override
  ConsumerState<RepaymentSheet> createState() => _RepaymentSheetState();
}

class _RepaymentSheetState extends ConsumerState<RepaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime _date = DateTime.now();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.lending.outstanding.toEditableString();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final currency = widget.lending.currency;
    final amount = Money.tryParse(_amountController.text, currency);
    if (amount == null || amount.isZero || amount.isNegative) {
      AppFeedback.showValidation(context, 'Enter an amount greater than zero.');
      return;
    }
    if (amount > widget.lending.outstanding) {
      AppFeedback.showValidation(
        context,
        'At most ${widget.lending.outstanding.format()} is still outstanding.',
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await ref.read(lendingControllerProvider.notifier).recordRepayment(
            lending: widget.lending,
            amount: amount,
            date: _date,
            notes: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
          );

      if (!mounted) return;
      Navigator.of(context).pop();
      AppFeedback.showSuccess(context, 'Repayment recorded');
    } on Object catch (error) {
      if (mounted) AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.lending.currency;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.lending.kind.isReceivable
                    ? 'Repayment from ${widget.lending.personName}'
                    : 'Repayment to ${widget.lending.personName}',
                style: context.text.titleLarge,
              ),
              AppSpacing.gapSm,
              Text(
                '${widget.lending.outstanding.format()} still outstanding',
                style: context.text.bodySmall,
              ),
              AppSpacing.gapXl,

              AmountField(
                controller: _amountController,
                currency: currency,
                autofocus: true,
                validator: (value) =>
                    Validators.amount(value, currency: currency),
              ),
              AppSpacing.gapXl,

              PickerField(
                label: 'Date',
                value: DateDisplay.dayMonthYear(_date),
                leading: const Icon(Icons.event_outlined, size: 20),
                onTap: () async {
                  final picked = await DateTimePickers.pickTransactionDate(
                    context,
                    initial: _date,
                  );
                  if (picked != null) setState(() => _date = picked);
                },
              ),
              AppSpacing.gapLg,

              TextFormField(
                controller: _noteController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  hintText: 'Optional',
                ),
              ),
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
                    : const Text('Record repayment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LendingMenu extends ConsumerWidget {
  const _LendingMenu({required this.lending});

  final LendingRecord lending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (value) async {
        switch (value) {
          case 'rename':
            await _rename(context, ref);
          case 'delete':
            await _delete(context, ref);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'rename',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Edit name or notes'),
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

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController(text: lending.personName);
    final notesController = TextEditingController(text: lending.notes ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            AppSpacing.gapMd,
            TextField(
              controller: notesController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != true || nameController.text.trim().isEmpty) return;
    if (!context.mounted) return;

    await AppFeedback.runWithProgress(
      context,
      successMessage: 'Updated',
      action: () async {
        await ref.read(lendingControllerProvider.notifier).save(
              lending.copyWith(
                personName: nameController.text.trim(),
                notes: notesController.text.trim().isEmpty
                    ? null
                    : notesController.text.trim(),
              ),
            );
        return true;
      },
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await AppFeedback.confirm(
      context,
      title: 'Delete this record?',
      message: 'This also removes every transaction it produced and reverses '
          'their effect on your account balance.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final done = await AppFeedback.runWithProgress(
      context,
      successMessage: 'Deleted',
      action: () async {
        await ref.read(lendingControllerProvider.notifier).delete(lending.id);
        return true;
      },
    );

    if (done == true && context.mounted) context.pop();
  }
}
