import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/models/account.dart';
import '../../../shared/models/bill.dart';
import '../../../shared/models/category.dart';
import '../../../shared/providers/account_providers.dart';
import '../../../shared/providers/planning_providers.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/pickers.dart';
import '../../../shared/widgets/state_views.dart';

/// Create or edit a bill.
class BillFormScreen extends ConsumerStatefulWidget {
  const BillFormScreen({super.key, this.billId});

  final String? billId;

  bool get isEditing => billId != null;

  @override
  ConsumerState<BillFormScreen> createState() => _BillFormScreenState();
}

class _BillFormScreenState extends ConsumerState<BillFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _reminderController = TextEditingController(text: '3');

  DateTime _dueDate = DateTime.now().add(const Duration(days: 7));
  RecurrenceFrequency? _frequency = RecurrenceFrequency.monthly;
  Category? _category;
  Account? _account;
  bool _isLoaded = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    _reminderController.dispose();
    super.dispose();
  }

  void _hydrate(Bill bill) {
    if (_isLoaded) return;
    _isLoaded = true;

    _nameController.text = bill.name;
    _amountController.text = bill.amount.toEditableString();
    _notesController.text = bill.notes ?? '';
    _reminderController.text = '${bill.reminderDays}';
    _dueDate = bill.dueDate;
    _frequency = bill.frequency;
    _category = bill.category;
    _account = bill.account ?? ref.read(accountByIdProvider(bill.accountId));
  }

  Future<void> _submit(Bill? existing) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final String currency = _account?.currency ?? ref.read(currencyProvider);
    final amount = Money.tryParse(_amountController.text, currency);
    if (amount == null || amount.isZero) {
      AppFeedback.showValidation(context, 'Enter the bill amount.');
      return;
    }

    context.hideKeyboard();
    setState(() => _isSubmitting = true);
    final controller = ref.read(billsControllerProvider.notifier);
    final reminderDays = int.tryParse(_reminderController.text.trim()) ?? 3;

    try {
      if (existing != null) {
        await controller.save(
          existing.copyWith(
            name: _nameController.text.trim(),
            amount: amount,
            dueDate: _dueDate,
            categoryId: _category?.id,
            accountId: _account?.id,
            frequency: _frequency,
            reminderDays: reminderDays,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          ),
        );
      } else {
        await controller.create(
          Bill(
            id: '',
            userId: '',
            name: _nameController.text.trim(),
            amount: amount,
            dueDate: _dueDate,
            categoryId: _category?.id,
            accountId: _account?.id,
            frequency: _frequency,
            reminderDays: reminderDays,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
      }

      if (!mounted) return;
      AppFeedback.showSuccess(
        context,
        existing != null ? 'Bill updated' : 'Bill added',
      );
      context.pop();
    } on Object catch (error) {
      if (mounted) AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isEditing) {
      final bill = ref.watch(billByIdProvider(widget.billId!));
      if (bill == null) {
        final bills = ref.watch(billsControllerProvider);
        return bills.view(
          (_) => const Scaffold(
            body: EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Bill not found',
              message: 'It may have been deleted.',
            ),
          ),
          loading: const Scaffold(body: LoadingView()),
        );
      }
      _hydrate(bill);
      return _buildForm(context, bill);
    }

    return _buildForm(context, null);
  }

  Widget _buildForm(BuildContext context, Bill? existing) {
    final String currency = _account?.currency ?? ref.watch(currencyProvider);
    final accounts = ref.watch(activeAccountsProvider);
    final categories =
        ref.watch(categoriesByKindProvider(CategoryKind.expense));

    return Scaffold(
      appBar: AppBar(
        title: Text(existing != null ? 'Edit bill' : 'Add bill'),
        actions: [
          if (existing != null)
            IconButton
              (
              onPressed: () => _delete(existing),
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Delete',
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.page),
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: existing == null,
                textCapitalization: TextCapitalization.words,
                validator: (value) =>
                    Validators.required(value, field: 'Bill name'),
                decoration: const InputDecoration(
                  labelText: 'Bill name *',
                  hintText: 'Electricity, Internet, Insurance…',
                  prefixIcon: Icon(Icons.receipt_long_outlined),
                ),
              ),
              AppSpacing.gapLg,

              AmountField(
                controller: _amountController,
                currency: currency,
                label: 'Amount',
                validator: (value) =>
                    Validators.amount(value, currency: currency),
              ),
              AppSpacing.gapLg,

              PickerField(
                label: 'Due date',
                isRequired: true,
                value: '${DateDisplay.dayMonthYear(_dueDate)} · '
                    '${DateDisplay.dueDescription(_dueDate)}',
                leading: const Icon(Icons.event_outlined, size: 20),
                onTap: () async {
                  final picked = await DateTimePickers.pickFutureDate(
                    context,
                    initial: _dueDate,
                    helpText: 'Due date',
                  );
                  if (picked != null) setState(() => _dueDate = picked);
                },
              ),
              AppSpacing.gapLg,

              PickerField(
                label: 'Repeats',
                value: _frequency?.label ?? 'One-off bill',
                leading: Icon(
                  _frequency == null
                      ? Icons.looks_one_outlined
                      : Icons.repeat_rounded,
                  size: 20,
                ),
                onTap: () => _pickFrequency(context),
              ),
              AppSpacing.gapLg,

              PickerField(
                label: 'Category',
                value: _category?.name,
                placeholder: 'Optional',
                leading: _category == null
                    ? null
                    : Icon(
                        _category!.icon,
                        size: 20,
                        color: _category!.color,
                      ),
                onTap: () async {
                  final picked = await CategoryPicker.show(
                    context,
                    categories: categories,
                    selectedId: _category?.id,
                    allowNone: true,
                  );
                  if (picked != null) {
                    setState(() => _category =
                        CategoryPicker.isNone(picked) ? null : picked);
                  }
                },
              ),
              AppSpacing.gapLg,

              PickerField(
                label: 'Usually paid from',
                value: _account?.name,
                placeholder: 'Optional',
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

              TextFormField(
                controller: _reminderController,
                keyboardType: TextInputType.number,
                validator: Validators.reminderDays,
                decoration: const InputDecoration(
                  labelText: 'Remind me this many days before',
                  prefixIcon: Icon(Icons.notifications_none_rounded),
                  suffixText: 'days',
                ),
              ),
              AppSpacing.gapLg,

              TextFormField(
                controller: _notesController,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  alignLabelWithHint: true,
                ),
              ),

              AppSpacing.gapXxl,
              FilledButton(
                onPressed: _isSubmitting ? null : () => _submit(existing),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(existing != null ? 'Save changes' : 'Add bill'),
              ),
              AppSpacing.gapXxl,
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFrequency(BuildContext context) async {
    final picked = await AppFeedback.showSheet<Object>(
      context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.sm,
              ),
              child: Text('How often?', style: context.text.titleLarge),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.looks_one_outlined),
              title: Text('One-off bill', style: context.text.titleSmall),
              subtitle: Text(
                'Does not repeat',
                style: context.text.bodySmall,
              ),
              trailing: _frequency == null
                  ? Icon(Icons.check_rounded, color: context.colors.primary)
                  : null,
              onTap: () => Navigator.of(context).pop('none'),
            ),
            for (final frequency in RecurrenceFrequency.values)
              if (frequency != RecurrenceFrequency.custom)
                ListTile(
                  leading: const Icon(Icons.repeat_rounded),
                  title: Text(frequency.label, style: context.text.titleSmall),
                  trailing: frequency == _frequency
                      ? Icon(Icons.check_rounded, color: context.colors.primary)
                      : null,
                  onTap: () => Navigator.of(context).pop(frequency),
                ),
          ],
        ),
      ),
    );

    if (picked == null) return;
    setState(() {
      _frequency = picked == 'none' ? null : picked as RecurrenceFrequency;
    });
  }

  Future<void> _delete(Bill bill) async {
    final confirmed = await AppFeedback.confirm(
      context,
      title: 'Delete bill?',
      message: 'The reminder is removed. Payments you already recorded stay in '
          'your transactions.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    final done = await AppFeedback.runWithProgress(
      context,
      successMessage: 'Bill deleted',
      action: () async {
        await ref.read(billsControllerProvider.notifier).delete(bill.id);
        return true;
      },
    );

    if (done == true && mounted) context.pop();
  }
}
