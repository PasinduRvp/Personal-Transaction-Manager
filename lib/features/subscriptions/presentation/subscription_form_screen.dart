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

/// Create or edit a subscription.
class SubscriptionFormScreen extends ConsumerStatefulWidget {
  const SubscriptionFormScreen({super.key, this.subscriptionId});

  final String? subscriptionId;

  bool get isEditing => subscriptionId != null;

  @override
  ConsumerState<SubscriptionFormScreen> createState() =>
      _SubscriptionFormScreenState();
}

class _SubscriptionFormScreenState
    extends ConsumerState<SubscriptionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _intervalController = TextEditingController();
  final _reminderController = TextEditingController(text: '2');
  final _notesController = TextEditingController();

  RecurrenceFrequency _frequency = RecurrenceFrequency.monthly;
  DateTime _nextRenewal = DateTime.now().add(const Duration(days: 30));
  Category? _category;
  Account? _account;
  PaymentMethod? _paymentMethod;
  bool _isActive = true;
  bool _isLoaded = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _intervalController.dispose();
    _reminderController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _hydrate(Subscription subscription) {
    if (_isLoaded) return;
    _isLoaded = true;

    _nameController.text = subscription.name;
    _amountController.text = subscription.amount.toEditableString();
    _intervalController.text = '${subscription.customIntervalDays ?? ''}';
    _reminderController.text = '${subscription.reminderDays}';
    _notesController.text = subscription.notes ?? '';
    _frequency = subscription.frequency;
    _nextRenewal = subscription.nextRenewalDate;
    _category = subscription.category;
    _account = subscription.account ??
        ref.read(accountByIdProvider(subscription.accountId));
    _paymentMethod = subscription.paymentMethod;
    _isActive = subscription.isActive;
  }

  Money? get _amount {
    final String currency = _account?.currency ?? ref.read(currencyProvider);
    return Money.tryParse(_amountController.text, currency);
  }

  Future<void> _submit(Subscription? existing) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final amount = _amount;
    if (amount == null || amount.isZero) {
      AppFeedback.showValidation(context, 'Enter the subscription cost.');
      return;
    }

    final customDays = _frequency == RecurrenceFrequency.custom
        ? int.tryParse(_intervalController.text.trim())
        : null;
    if (_frequency == RecurrenceFrequency.custom &&
        (customDays == null || customDays < 1)) {
      AppFeedback.showValidation(
        context,
        'Enter how many days between charges.',
      );
      return;
    }

    context.hideKeyboard();
    setState(() => _isSubmitting = true);
    final controller = ref.read(subscriptionsControllerProvider.notifier);
    final reminderDays = int.tryParse(_reminderController.text.trim()) ?? 2;
    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();

    try {
      if (existing != null) {
        await controller.save(
          existing.copyWith(
            name: _nameController.text.trim(),
            amount: amount,
            frequency: _frequency,
            nextRenewalDate: _nextRenewal,
            categoryId: _category?.id,
            accountId: _account?.id,
            customIntervalDays: customDays,
            paymentMethod: _paymentMethod,
            reminderDays: reminderDays,
            notes: notes,
            isActive: _isActive,
          ),
        );
      } else {
        await controller.create(
          Subscription(
            id: '',
            userId: '',
            name: _nameController.text.trim(),
            amount: amount,
            frequency: _frequency,
            nextRenewalDate: _nextRenewal,
            categoryId: _category?.id,
            accountId: _account?.id,
            startDate: DateTime.now(),
            customIntervalDays: customDays,
            paymentMethod: _paymentMethod,
            reminderDays: reminderDays,
            notes: notes,
            isActive: _isActive,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
      }

      if (!mounted) return;
      AppFeedback.showSuccess(
        context,
        existing != null ? 'Subscription updated' : 'Subscription added',
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
      final subscription =
          ref.watch(subscriptionByIdProvider(widget.subscriptionId!));
      if (subscription == null) {
        final all = ref.watch(subscriptionsControllerProvider);
        return all.view(
          (_) => const Scaffold(
            body: EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Subscription not found',
              message: 'It may have been deleted.',
            ),
          ),
          loading: const Scaffold(body: LoadingView()),
        );
      }
      _hydrate(subscription);
      return _buildForm(context, subscription);
    }

    return _buildForm(context, null);
  }

  Widget _buildForm(BuildContext context, Subscription? existing) {
    final String currency = _account?.currency ?? ref.watch(currencyProvider);
    final accounts = ref.watch(activeAccountsProvider);
    final categories =
        ref.watch(categoriesByKindProvider(CategoryKind.expense));

    final amount = _amount;
    final monthlyEquivalent = amount == null
        ? null
        : amount *
            AppDateUtils.occurrencesPerMonth(
              _frequency,
              customDays: int.tryParse(_intervalController.text.trim()) ?? 30,
            );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          existing != null ? 'Edit subscription' : 'Add subscription',
        ),
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
              TextFormField(
                controller: _nameController,
                autofocus: existing == null,
                textCapitalization: TextCapitalization.words,
                validator: (value) =>
                    Validators.required(value, field: 'Name'),
                decoration: const InputDecoration(
                  labelText: 'Service name *',
                  hintText: 'Netflix, Spotify, iCloud…',
                  prefixIcon: Icon(Icons.subscriptions_outlined),
                ),
              ),
              AppSpacing.gapLg,

              AmountField(
                controller: _amountController,
                currency: currency,
                label: 'Cost per billing period',
                onChanged: (_) => setState(() {}),
                validator: (value) =>
                    Validators.amount(value, currency: currency),
              ),
              AppSpacing.gapLg,

              PickerField(
                label: 'Billing frequency',
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
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Days between charges *',
                    prefixIcon: Icon(Icons.timelapse_rounded),
                    suffixText: 'days',
                  ),
                ),
              ],

              // Shown only when it adds information — for a monthly plan the
              // normalised figure is the same number.
              if (monthlyEquivalent != null &&
                  _frequency != RecurrenceFrequency.monthly) ...[
                AppSpacing.gapMd,
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: context.palette.surfaceAlt,
                    borderRadius: AppRadius.mdAll,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calculate_outlined,
                        size: 18,
                        color: context.palette.textSecondary,
                      ),
                      AppSpacing.hGapMd,
                      Expanded(
                        child: Text(
                          'That works out to about '
                          '${monthlyEquivalent.format()} a month',
                          style: context.text.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              AppSpacing.gapLg,

              PickerField(
                label: 'Next renewal',
                isRequired: true,
                value: '${DateDisplay.dayMonthYear(_nextRenewal)} · '
                    '${DateDisplay.dueDescription(_nextRenewal)}',
                leading: const Icon(Icons.event_outlined, size: 20),
                onTap: () async {
                  final picked = await DateTimePickers.pickFutureDate(
                    context,
                    initial: _nextRenewal,
                    helpText: 'Next renewal date',
                  );
                  if (picked != null) setState(() => _nextRenewal = picked);
                },
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
                label: 'Charged to',
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

              PickerField(
                label: 'Payment method',
                value: _paymentMethod?.label,
                placeholder: 'Optional',
                leading: _paymentMethod == null
                    ? null
                    : Icon(
                        PaymentMethodPicker.iconFor(_paymentMethod!),
                        size: 20,
                      ),
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

              TextFormField(
                controller: _reminderController,
                keyboardType: TextInputType.number,
                validator: Validators.reminderDays,
                decoration: const InputDecoration(
                  labelText: 'Remind me before renewal',
                  prefixIcon: Icon(Icons.notifications_none_rounded),
                  suffixText: 'days',
                ),
              ),
              AppSpacing.gapLg,

              AppCard(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                  title: Text('Active', style: context.text.titleSmall),
                  subtitle: Text(
                    'Paused subscriptions are excluded from your monthly total',
                    style: context.text.bodySmall,
                  ),
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
                    : Text(
                        existing != null
                            ? 'Save changes'
                            : 'Add subscription',
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
              child: Text('Billing frequency', style: context.text.titleLarge),
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

  Future<void> _delete(Subscription subscription) async {
    final confirmed = await AppFeedback.confirm(
      context,
      title: 'Delete subscription?',
      message: 'It is removed from your monthly cost and its reminders stop.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    final done = await AppFeedback.runWithProgress(
      context,
      successMessage: 'Subscription deleted',
      action: () async {
        await ref
            .read(subscriptionsControllerProvider.notifier)
            .delete(subscription.id);
        return true;
      },
    );

    if (done == true && mounted) context.pop();
  }
}
