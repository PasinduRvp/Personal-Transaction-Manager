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

  final _transferController = TextEditingController();
  final _chargeController = TextEditingController();
  final _chargeDescriptionController =
      TextEditingController(text: 'Bank Transfer Fee');

  LendingKind _kind = LendingKind.lent;
  LendingMethod _method = LendingMethod.wallet;
  Account? _account;
  DateTime _date = DateTime.now();
  DateTime? _dueDate;
  bool _isSubmitting = false;

  /// The charge only applies to money you lent by bank transfer. Borrowing
  /// never carries one, and the other methods have nothing to charge.
  bool get _chargeApplies =>
      _kind == LendingKind.lent && _method.allowsAdditionalCharge;

  @override
  void dispose() {
    _personController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    _transferController.dispose();
    _chargeController.dispose();
    _chargeDescriptionController.dispose();
    super.dispose();
  }

  /// Drops any charge the user typed before switching away from a method that
  /// can carry one, so a stale figure cannot reach the ledger.
  void _clearChargeIfUnavailable() {
    if (_chargeApplies) return;
    _chargeController.clear();
    _chargeDescriptionController.text = 'Bank Transfer Fee';
  }

  static IconData _iconForMethod(LendingMethod method) => switch (method) {
        LendingMethod.wallet => Icons.account_balance_wallet_outlined,
        LendingMethod.bankTransfer => Icons.account_balance_outlined,
        LendingMethod.other => Icons.more_horiz_rounded,
      };

  Future<void> _pickMethod() async {
    final picked = await AppFeedback.showSheet<LendingMethod>(
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
              child: Text(
                _kind == LendingKind.lent
                    ? 'How did you send it?'
                    : 'How did you receive it?',
                style: context.text.titleLarge,
              ),
            ),
            const Divider(height: 1),
            for (final method in LendingMethod.values)
              ListTile(
                leading: Icon(_iconForMethod(method)),
                title: Text(method.label, style: context.text.titleSmall),
                trailing: method == _method
                    ? Icon(Icons.check_rounded, color: context.colors.primary)
                    : null,
                onTap: () => Navigator.of(context).pop(method),
              ),
          ],
        ),
      ),
    );

    if (picked == null) return;
    setState(() {
      _method = picked;
      _clearChargeIfUnavailable();
    });
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
      // Only read the charge when it actually applies, so a value typed
      // before switching method cannot leak into the record.
      final charge = _chargeApplies
          ? Money.tryParse(_chargeController.text, account.currency)
          : null;

      // Blank means it moved exactly what is owed, which is the usual case.
      final transferred = _transferController.text.trim().isEmpty
          ? null
          : Money.tryParse(_transferController.text, account.currency);

      await ref.read(lendingControllerProvider.notifier).create(
            personName: _personController.text.trim(),
            kind: _kind,
            principal: amount,
            accountId: account.id,
            method: _method,
            transferAmount: transferred,
            additionalCharge: charge,
            chargeDescription: _chargeApplies
                ? _chargeDescriptionController.text.trim()
                : null,
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
                onSelectionChanged: (selected) => setState(() {
                  _kind = selected.first;
                  // Borrowing never carries a lender's bank charge.
                  _clearChargeIfUnavailable();
                }),
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
                label: _kind == LendingKind.lent
                    ? 'Transfer method'
                    : 'Received method',
                isRequired: true,
                value: _method.label,
                leading: Icon(_iconForMethod(_method), size: 20),
                onTap: _pickMethod,
              ),
              AppSpacing.gapLg,

              // Optional, and blank means "the same as the amount above".
              //
              // Two always-visible amount fields that are equal in almost every
              // case would be double entry for no gain, so this one only needs
              // filling in when the money that actually left the account
              // differs from the debt — a rounded-down transfer, say. What is
              // owed is still the Amount field; this never changes it.
              AmountField(
                controller: _transferController,
                currency: currency,
                label: 'Transfer amount (optional)',
                compact: true,
                helperText: _kind == LendingKind.lent
                    ? 'Only if what left your account differs from the amount '
                        'above'
                    : 'Only if what reached your account differs from the '
                        'amount above',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  final transferred = Money.tryParse(value, currency);
                  if (transferred == null) return 'Enter a valid amount';
                  if (transferred.isZero || transferred.isNegative) {
                    return 'The transfer must be greater than zero';
                  }
                  return null;
                },
              ),
              AppSpacing.gapLg,

              // Only a bank transfer charges a fee, and only when you are the
              // one sending the money.
              if (_chargeApplies) ...[
                AmountField(
                  controller: _chargeController,
                  currency: currency,
                  label: 'Additional charge (optional)',
                  compact: true,
                  helperText: 'What your bank charged you to send it',
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final charge = Money.tryParse(value, currency);
                    if (charge == null) return 'Enter a valid amount';
                    if (charge.isNegative) {
                      return 'The charge cannot be negative';
                    }
                    return null;
                  },
                ),
                AppSpacing.gapLg,
                TextFormField(
                  controller: _chargeDescriptionController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Charge description',
                    prefixIcon: Icon(Icons.receipt_long_outlined),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.xs,
                    left: AppSpacing.md,
                  ),
                  child: Text(
                    'Recorded as your own expense. It is never added to what '
                    '${_personController.text.trim().isEmpty ? 'they' : _personController.text.trim()} owes you.',
                    style: context.text.bodySmall,
                  ),
                ),
                AppSpacing.gapLg,
              ],

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
