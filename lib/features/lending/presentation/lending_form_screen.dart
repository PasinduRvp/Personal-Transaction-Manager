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
import '../../../shared/providers/account_providers.dart';
import '../../../shared/providers/planning_providers.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/pickers.dart';

/// Records money lent to, or borrowed from, someone — the principal amount,
/// who it is, and which of the user's accounts it moved through.
class LendingFormScreen extends ConsumerStatefulWidget {
  const LendingFormScreen({super.key});

  @override
  ConsumerState<LendingFormScreen> createState() => _LendingFormScreenState();
}

class _LendingFormScreenState extends ConsumerState<LendingFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _personController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  LendingKind _kind = LendingKind.lent;
  Account? _account;
  DateTime _date = DateTime.now();
  DateTime? _dueDate;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _personController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final account = _account;
    if (account == null) {
      AppFeedback.showValidation(context, 'Choose an account.');
      return;
    }

    final amount = Money.tryParse(_amountController.text, account.currency);
    if (amount == null || amount.isZero || amount.isNegative) {
      AppFeedback.showValidation(
        context,
        'Enter an amount greater than zero.',
      );
      return;
    }

    context.hideKeyboard();
    setState(() => _isSubmitting = true);

    try {
      await ref.read(lendingControllerProvider.notifier).create(
            personName: _personController.text.trim(),
            kind: _kind,
            principal: amount,
            accountId: account.id,
            date: _date,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
            dueDate: _dueDate,
          );

      if (!mounted) return;
      AppFeedback.showSuccess(context, 'Recorded');
      context.pop();
    } on Object catch (error) {
      if (mounted) AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(activeAccountsProvider);
    final String currency = _account?.currency ?? ref.watch(currencyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Record lending')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.page),
            children: [
              SegmentedButton<LendingKind>(
                segments: const [
                  ButtonSegment(
                    value: LendingKind.lent,
                    label: Text('I lent'),
                    icon: Icon(Icons.call_made_rounded),
                  ),
                  ButtonSegment(
                    value: LendingKind.borrowed,
                    label: Text('I borrowed'),
                    icon: Icon(Icons.call_received_rounded),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (selected) =>
                    setState(() => _kind = selected.first),
              ),
              AppSpacing.gapXl,

              TextFormField(
                controller: _personController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                validator: (value) =>
                    Validators.required(value, field: 'Their name'),
                decoration: InputDecoration(
                  labelText: _kind == LendingKind.lent
                      ? 'Who did you lend to? *'
                      : 'Who did you borrow from? *',
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
              ),
              AppSpacing.gapLg,

              AmountField(
                controller: _amountController,
                currency: currency,
                label: 'Amount',
                autofocus: false,
                validator: (value) =>
                    Validators.amount(value, currency: currency),
              ),
              AppSpacing.gapLg,

              PickerField(
                label: _kind == LendingKind.lent
                    ? 'From account'
                    : 'To account',
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
                label: 'Date',
                value: DateDisplay.dayMonthYear(_date),
                leading: const Icon(Icons.event_outlined, size: 20),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
              ),
              AppSpacing.gapLg,

              PickerField(
                label: 'Expected back by',
                value: _dueDate == null
                    ? null
                    : DateDisplay.dayMonthYear(_dueDate!),
                placeholder: 'Optional',
                leading: const Icon(Icons.event_available_outlined, size: 20),
                trailing: _dueDate == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() => _dueDate = null),
                        tooltip: 'Clear',
                      ),
                onTap: () async {
                  final picked = await DateTimePickers.pickFutureDate(
                    context,
                    initial: _dueDate ??
                        DateTime.now().add(const Duration(days: 30)),
                    helpText: 'Expected back by',
                  );
                  if (picked != null) setState(() => _dueDate = picked);
                },
              ),
              AppSpacing.gapLg,

              TextFormField(
                controller: _notesController,
                maxLines: 3,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  alignLabelWithHint: true,
                ),
              ),

              AppSpacing.gapXl,
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
                    : const Text('Record'),
              ),
              AppSpacing.gapXxl,
            ],
          ),
        ),
      ),
    );
  }
}
