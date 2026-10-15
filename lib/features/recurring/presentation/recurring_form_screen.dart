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
import '../../../shared/models/category.dart';
import '../../../shared/models/subscription.dart';
import '../../../shared/providers/account_providers.dart';
import '../../../shared/providers/planning_providers.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/pickers.dart';
import '../../../shared/widgets/state_views.dart';

/// Create or edit a recurring transaction schedule.
class RecurringFormScreen extends ConsumerStatefulWidget {
  const RecurringFormScreen({super.key, this.recurringId});

  final String? recurringId;

  bool get isEditing => recurringId != null;

  @override
  ConsumerState<RecurringFormScreen> createState() =>
      _RecurringFormScreenState();
}

class _RecurringFormScreenState extends ConsumerState<RecurringFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();
  final _intervalController = TextEditingController();

  TransactionType _type = TransactionType.expense;
  RecurrenceFrequency _frequency = RecurrenceFrequency.monthly;
  Account? _account;
  Account? _toAccount;
  Category? _category;
  PaymentMethod? _paymentMethod;
  DateTime _startDate = DateTime.now();
  DateTime _nextExecution = DateTime.now().add(const Duration(days: 30));
  DateTime? _endDate;
  bool _autoPost = true;
  bool _isActive = true;
  bool _isLoaded = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _merchantController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  void _hydrate(RecurringTransaction schedule) {
    if (_isLoaded) return;
    _isLoaded = true;

    _nameController.text = schedule.name;
    _amountController.text = schedule.amount.toEditableString();
    _merchantController.text = schedule.merchant ?? '';
    _intervalController.text = '${schedule.customIntervalDays ?? ''}';
    _type = schedule.type;
    _frequency = schedule.frequency;
    _account = schedule.account ??
        ref.read(accountByIdProvider(schedule.accountId));
    _toAccount = ref.read(accountByIdProvider(schedule.transferToAccountId));
    _category = schedule.category;
    _paymentMethod = schedule.paymentMethod;
    _startDate = schedule.startDate;
    _nextExecution = schedule.nextExecutionDate;
    _endDate = schedule.endDate;
    _autoPost = schedule.autoPost;
    _isActive = schedule.isActive;
  }

  void _applyDefaults() {
    if (_isLoaded) return;
    _isLoaded = true;
    _account = ref.read(defaultAccountProvider);
  }

  Future<void> _submit(RecurringTransaction? existing) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final account = _account;
    if (account == null) {
      AppFeedback.showValidation(context, 'Choose an account.');
      return;
    }

    final amount = Money.tryParse(_amountController.text, account.currency);
    if (amount == null || amount.isZero) {
      AppFeedback.showValidation(context, 'Enter an amount.');
      return;
    }

    if (_type.isTransfer) {
      final error = Validators.transferAccounts(account.id, _toAccount?.id);
      if (error != null) {
        AppFeedback.showValidation(context, error);
        return;
      }
    }

    final customDays = _frequency == RecurrenceFrequency.custom
        ? int.tryParse(_intervalController.text.trim())
        : null;
    if (_frequency == RecurrenceFrequency.custom &&
        (customDays == null || customDays < 1)) {
      AppFeedback.showValidation(context, 'Enter how many days between posts.');
      return;
    }

    if (_endDate != null && _endDate!.isBefore(_startDate)) {
      AppFeedback.showValidation(
        context,
        'The end date must be after the start date.',
      );
      return;
    }

    context.hideKeyboard();
    setState(() => _isSubmitting = true);
    final controller = ref.read(recurringControllerProvider.notifier);
    final merchant = _merchantController.text.trim().isEmpty
        ? null
        : _merchantController.text.trim();

    try {
      if (existing != null) {
        await controller.save(
          existing.copyWith(
            name: _nameController.text.trim(),
            type: _type,
            amount: amount,
            accountId: account.id,
            categoryId: _type.isTransfer ? null : _category?.id,
            frequency: _frequency,
            startDate: _startDate,
            endDate: _endDate,
            nextExecutionDate: _nextExecution,
            customIntervalDays: customDays,
            merchant: merchant,
            paymentMethod: _paymentMethod,
            transferToAccountId: _type.isTransfer ? _toAccount?.id : null,
            autoPost: _autoPost,
            isActive: _isActive,
          ),
        );
      } else {
        await controller.create(
          RecurringTransaction(
            id: '',
            userId: '',
            name: _nameController.text.trim(),
            type: _type,
            amount: amount,
            accountId: account.id,
            categoryId: _type.isTransfer ? null : _category?.id,
            frequency: _frequency,
            startDate: _startDate,
            endDate: _endDate,
            nextExecutionDate: _nextExecution,
            customIntervalDays: customDays,
            merchant: merchant,
            paymentMethod: _paymentMethod,
            transferToAccountId: _type.isTransfer ? _toAccount?.id : null,
            autoPost: _autoPost,
            isActive: _isActive,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
      }

      if (!mounted) return;
      AppFeedback.showSuccess(
        context,
        existing != null ? 'Schedule updated' : 'Schedule created',
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
      final schedule = ref.watch(recurringByIdProvider(widget.recurringId!));
      if (schedule == null) {
        final all = ref.watch(recurringControllerProvider);
        return all.view(
          (_) => const Scaffold(
            body: EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Schedule not found',
              message: 'It may have been deleted.',
            ),
          ),
          loading: const Scaffold(body: LoadingView()),
        );
      }
      _hydrate(schedule);
      return _buildForm(context, schedule);
    }

    _applyDefaults();
    return _buildForm(context, null);
  }

  Widget _buildForm(BuildContext context, RecurringTransaction? existing) {
    final String currency = _account?.currency ?? ref.watch(currencyProvider);
    final accounts = ref.watch(activeAccountsProvider);
    final categories = ref.watch(
      categoriesByKindProvider(
        _type == TransactionType.income
            ? CategoryKind.income
            : CategoryKind.expense,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(existing != null ? 'Edit schedule' : 'New schedule'),
        actions: [
          if (existing != null)
            IconButton(
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
              SegmentedTypeSelector<TransactionType>(
                options: TransactionType.values,
                selected: _type,
                labelFor: (type) => type.label,
                iconFor: (type) => switch (type) {
                  TransactionType.expense => Icons.arrow_upward_rounded,
                  TransactionType.income => Icons.arrow_downward_rounded,
                  TransactionType.transfer => Icons.swap_horiz_rounded,
                },
                colorFor: (type) => switch (type) {
                  TransactionType.expense => context.palette.expense,
                  TransactionType.income => context.palette.income,
                  TransactionType.transfer => context.palette.transfer,
                },
                onChanged: (type) => setState(() {
                  _type = type;
                  _category = null;
                }),
              ),
              AppSpacing.gapXl,

              TextFormField(
                controller: _nameController,
                autofocus: existing == null,
                textCapitalization: TextCapitalization.words,
                validator: (value) =>
                    Validators.required(value, field: 'Name'),
                decoration: const InputDecoration(
                  labelText: 'Schedule name *',
                  hintText: 'Monthly salary, Rent, Loan payment…',
                  prefixIcon: Icon(Icons.repeat_rounded),
                ),
              ),
              AppSpacing.gapLg,

              AmountField(
                controller: _amountController,
                currency: currency,
                validator: (value) =>
                    Validators.amount(value, currency: currency),
              ),
              AppSpacing.gapLg,

              PickerField(
                label: _type.isTransfer ? 'From account' : 'Account',
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
                    excludeId: _type.isTransfer ? _toAccount?.id : null,
                  );
                  if (picked != null) setState(() => _account = picked);
                },
              ),
              AppSpacing.gapLg,

              if (_type.isTransfer)
                PickerField(
                  label: 'To account',
                  isRequired: true,
                  value: _toAccount?.name,
                  leading: _toAccount == null
                      ? null
                      : IconBadge(
                          icon: _toAccount!.icon,
                          color: _toAccount!.color,
                          size: 24,
                          iconSize: 14,
                        ),
                  onTap: () async {
                    final picked = await AccountPicker.show(
                      context,
                      accounts: accounts,
                      selectedId: _toAccount?.id,
                      excludeId: _account?.id,
                      title: 'Transfer to',
                    );
                    if (picked != null) setState(() => _toAccount = picked);
                  },
                )
              else
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
                label: 'Frequency',
                isRequired: true,
                value: _frequency.label,
                leading: const Icon(Icons.event_repeat_outlined, size: 20),
                onTap: () => _pickFrequency(context),
              ),

              if (_frequency == RecurrenceFrequency.custom) ...[
                AppSpacing.gapLg,
                TextFormField(
                  controller: _intervalController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Days between posts *',
                    prefixIcon: Icon(Icons.timelapse_rounded),
                    suffixText: 'days',
                  ),
                ),
              ],
              AppSpacing.gapLg,

              Row(
                children: [
                  Expanded(
                    child: PickerField(
                      label: 'Starts',
                      value: DateDisplay.dayMonthYear(_startDate),
                      onTap: () async {
                        final picked = await DateTimePickers.pickFutureDate(
                          context,
                          initial: _startDate,
                          helpText: 'Start date',
                        );
                        if (picked != null) {
                          setState(() => _startDate = picked);
                        }
                      },
                    ),
                  ),
                  AppSpacing.hGapMd,
                  Expanded(
                    child: PickerField(
                      label: 'Ends',
                      value: _endDate == null
                          ? null
                          : DateDisplay.dayMonthYear(_endDate!),
                      placeholder: 'Never',
                      trailing: _endDate == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () =>
                                  setState(() => _endDate = null),
                              tooltip: 'Clear',
                            ),
                      onTap: () async {
                        final picked = await DateTimePickers.pickFutureDate(
                          context,
                          initial: _endDate ??
                              _startDate.add(const Duration(days: 365)),
                          helpText: 'End date',
                        );
                        if (picked != null) setState(() => _endDate = picked);
                      },
                    ),
                  ),
                ],
              ),
              AppSpacing.gapLg,

              PickerField(
                label: 'Next posts on',
                isRequired: true,
                value: DateDisplay.dayMonthYear(_nextExecution),
                leading: const Icon(Icons.schedule_outlined, size: 20),
                onTap: () async {
                  final picked = await DateTimePickers.pickFutureDate(
                    context,
                    initial: _nextExecution,
                    helpText: 'Next posting date',
                  );
                  if (picked != null) {
                    setState(() => _nextExecution = picked);
                  }
                },
              ),
              AppSpacing.gapLg,

              if (!_type.isTransfer) ...[
                TextFormField(
                  controller: _merchantController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: _type == TransactionType.income
                        ? 'Source'
                        : 'Merchant',
                    hintText: 'Optional',
                    prefixIcon: const Icon(Icons.storefront_outlined),
                  ),
                ),
                AppSpacing.gapLg,
                PickerField(
                  label: 'Payment method',
                  value: _paymentMethod?.label,
                  placeholder: 'Optional',
                  onTap: () async {
                    final picked = await PaymentMethodPicker.show(
                      context,
                      selected: _paymentMethod,
                    );
                    if (picked != null) {
                      setState(() => _paymentMethod = picked);
                    }
                  },
                ),
                AppSpacing.gapLg,
              ],

              AppCard(
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _autoPost,
                      onChanged: (value) => setState(() => _autoPost = value),
                      title: Text(
                        'Post automatically',
                        style: context.text.titleSmall,
                      ),
                      subtitle: Text(
                        // Drafts are PENDING transactions, which do not move a
                        // balance until confirmed — worth saying, because it
                        // explains why a balance has not changed.
                        _autoPost
                            ? 'Creates a confirmed transaction on each date'
                            : 'Creates a draft for you to confirm, which does '
                                'not change your balance until you do',
                        style: context.text.bodySmall,
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _isActive,
                      onChanged: (value) => setState(() => _isActive = value),
                      title: Text('Active', style: context.text.titleSmall),
                      subtitle: Text(
                        'Paused schedules do not post anything',
                        style: context.text.bodySmall,
                      ),
                    ),
                  ],
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
                    : Text(
                        existing != null
                            ? 'Save changes'
                            : 'Create schedule',
                      ),
              ),
              AppSpacing.gapXxl,
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFrequency(BuildContext context) async {
    final picked = await AppFeedback.showSheet<RecurrenceFrequency>(
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
            for (final frequency in RecurrenceFrequency.values)
              ListTile(
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

    if (picked != null) setState(() => _frequency = picked);
  }

  Future<void> _delete(RecurringTransaction schedule) async {
    final confirmed = await AppFeedback.confirm(
      context,
      title: 'Delete schedule?',
      message: 'No further transactions will be posted.',
      confirmLabel: 'Delete',
      isDestructive: true,
      consequences: const [
        'Transactions it already posted stay in your history — that money '
            'really moved.',
      ],
    );
    if (!confirmed || !mounted) return;

    final done = await AppFeedback.runWithProgress(
      context,
      successMessage: 'Schedule deleted',
      action: () async {
        await ref
            .read(recurringControllerProvider.notifier)
            .delete(schedule.id);
        return true;
      },
    );

    if (done == true && mounted) context.pop();
  }
}
