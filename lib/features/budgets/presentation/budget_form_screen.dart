import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/models/budget.dart';
import '../../../shared/models/category.dart';
import '../../../shared/providers/account_providers.dart';
import '../../../shared/providers/planning_providers.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/pickers.dart';
import '../../../shared/widgets/state_views.dart';

/// Create or edit a budget.
class BudgetFormScreen extends ConsumerStatefulWidget {
  const BudgetFormScreen({super.key, this.budgetId});

  final String? budgetId;

  bool get isEditing => budgetId != null;

  @override
  ConsumerState<BudgetFormScreen> createState() => _BudgetFormScreenState();
}

class _BudgetFormScreenState extends ConsumerState<BudgetFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _nameController = TextEditingController();

  BudgetPeriod _period = BudgetPeriod.monthly;
  Category? _category;
  bool _isOverall = false;
  int _threshold = 80;
  DateTime _startDate = AppDateUtils.startOfMonth(DateTime.now());
  DateTime? _endDate;
  bool _rollover = false;
  bool _isLoaded = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _hydrate(Budget budget) {
    if (_isLoaded) return;
    _isLoaded = true;

    _amountController.text = budget.amount.toEditableString();
    _nameController.text = budget.name ?? '';
    _period = budget.period;
    _category = budget.category;
    _isOverall = budget.isOverall;
    _threshold = budget.alertThreshold;
    _startDate = budget.startDate;
    _endDate = budget.endDate;
    _rollover = budget.rollover;
  }

  Future<void> _submit(Budget? existing) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (!_isOverall && _category == null) {
      AppFeedback.showValidation(
        context,
        'Choose a category, or make this an overall budget.',
      );
      return;
    }

    if (_period == BudgetPeriod.custom) {
      final error = Validators.dateRange(_startDate, _endDate);
      if (error != null) {
        AppFeedback.showValidation(context, error);
        return;
      }
    }

    final currency = ref.read(currencyProvider);
    final amount = Money.tryParse(_amountController.text, currency);
    if (amount == null || amount.isZero) {
      AppFeedback.showValidation(context, 'Enter a budget amount.');
      return;
    }

    context.hideKeyboard();
    setState(() => _isSubmitting = true);
    final controller = ref.read(budgetsControllerProvider.notifier);

    try {
      final name = _nameController.text.trim().isEmpty
          ? (_isOverall ? 'Overall' : _category?.name)
          : _nameController.text.trim();

      if (existing != null) {
        await controller.save(
          existing.copyWith(
            categoryId: _isOverall ? null : _category?.id,
            name: name,
            amount: amount,
            period: _period,
            startDate: _startDate,
            endDate: _period == BudgetPeriod.custom ? _endDate : null,
            alertThreshold: _threshold,
            rollover: _rollover,
          ),
        );
      } else {
        await controller.create(
          Budget(
            id: '',
            userId: '',
            categoryId: _isOverall ? null : _category?.id,
            name: name,
            amount: amount,
            period: _period,
            startDate: _startDate,
            endDate: _period == BudgetPeriod.custom ? _endDate : null,
            alertThreshold: _threshold,
            rollover: _rollover,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
      }

      if (!mounted) return;
      AppFeedback.showSuccess(
        context,
        existing != null ? 'Budget updated' : 'Budget created',
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
      final progress = ref.watch(budgetProgressByIdProvider(widget.budgetId!));
      if (progress == null) {
        final budgets = ref.watch(budgetsControllerProvider);
        return budgets.view(
          (_) => const Scaffold(
            body: EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Budget not found',
              message: 'It may have been deleted.',
            ),
          ),
          loading: const Scaffold(body: LoadingView()),
        );
      }
      _hydrate(progress.budget);
      return _buildForm(context, progress.budget);
    }

    return _buildForm(context, null);
  }

  Widget _buildForm(BuildContext context, Budget? existing) {
    final currency = ref.watch(currencyProvider);
    final categories =
        ref.watch(categoriesByKindProvider(CategoryKind.expense));
    final budgeted = ref.watch(budgetedCategoryIdsProvider);

    // A category that already has an active budget is not offered again: the
    // database enforces one active budget per category per period, so showing it
    // would only produce a confusing error on save.
    final available = categories
        .where((c) => !budgeted.contains(c.id) || c.id == _category?.id)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(existing != null ? 'Edit budget' : 'New budget'),
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
              AmountField(
                controller: _amountController,
                currency: currency,
                label: 'Budget amount',
                autofocus: existing == null,
                validator: (value) =>
                    Validators.amount(value, currency: currency),
              ),
              AppSpacing.gapXl,

              AppCard(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isOverall,
                  onChanged: existing != null
                      // Switching an existing budget between overall and
                      // category would change what its recorded spending means,
                      // so it is fixed after creation.
                      ? null
                      : (value) => setState(() {
                            _isOverall = value;
                            if (value) _category = null;
                          }),
                  title: Text(
                    'Overall budget',
                    style: context.text.titleSmall,
                  ),
                  subtitle: Text(
                    'Covers all expense categories together',
                    style: context.text.bodySmall,
                  ),
                ),
              ),
              AppSpacing.gapLg,

              if (!_isOverall) ...[
                PickerField(
                  label: 'Category',
                  isRequired: true,
                  value: _category?.name,
                  leading: _category == null
                      ? null
                      : Icon(
                          _category!.icon,
                          size: 20,
                          color: _category!.color,
                        ),
                  onTap: () async {
                    if (available.isEmpty) {
                      AppFeedback.showInfo(
                        context,
                        'Every expense category already has a budget.',
                      );
                      return;
                    }
                    final picked = await CategoryPicker.show(
                      context,
                      categories: available,
                      selectedId: _category?.id,
                      title: 'Budget category',
                    );
                    if (picked != null) {
                      setState(() => _category = picked);
                    }
                  },
                ),
                AppSpacing.gapLg,
              ],

              PickerField(
                label: 'Period',
                isRequired: true,
                value: _period.label,
                leading: const Icon(Icons.event_repeat_outlined, size: 20),
                onTap: () => _pickPeriod(context),
              ),
              AppSpacing.gapLg,

              if (_period == BudgetPeriod.custom) ...[
                Row(
                  children: [
                    Expanded(
                      child: PickerField(
                        label: 'Start',
                        value: DateDisplay.dayMonthYear(_startDate),
                        onTap: () async {
                          final picked = await DateTimePickers.pickFutureDate(
                            context,
                            initial: _startDate,
                            helpText: 'Budget start',
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
                        label: 'End',
                        value: _endDate == null
                            ? null
                            : DateDisplay.dayMonthYear(_endDate!),
                        onTap: () async {
                          final picked = await DateTimePickers.pickFutureDate(
                            context,
                            initial: _endDate ??
                                _startDate.add(const Duration(days: 30)),
                            helpText: 'Budget end',
                          );
                          if (picked != null) {
                            setState(() => _endDate = picked);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                AppSpacing.gapLg,
              ],

              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: _isOverall
                      ? 'Overall monthly'
                      : _category?.name ?? 'Optional',
                  prefixIcon: const Icon(Icons.label_outline_rounded),
                ),
              ),
              AppSpacing.gapXl,

              _ThresholdSelector(
                value: _threshold,
                onChanged: (value) => setState(() => _threshold = value),
              ),
              AppSpacing.gapLg,

              AppCard(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _rollover,
                  onChanged: (value) => setState(() => _rollover = value),
                  title: Text(
                    'Carry over unspent budget',
                    style: context.text.titleSmall,
                  ),
                  subtitle: Text(
                    'Anything left adds to next period',
                    style: context.text.bodySmall,
                  ),
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
                        existing != null ? 'Save changes' : 'Create budget',
                      ),
              ),
              AppSpacing.gapXxl,
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickPeriod(BuildContext context) async {
    final picked = await AppFeedback.showSheet<BudgetPeriod>(
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
              child: Text('Budget period', style: context.text.titleLarge),
            ),
            const Divider(height: 1),
            for (final period in BudgetPeriod.values)
              ListTile(
                title: Text(period.label, style: context.text.titleSmall),
                subtitle: Text(
                  switch (period) {
                    BudgetPeriod.weekly => 'Resets every Monday',
                    BudgetPeriod.monthly => 'Resets on the 1st',
                    BudgetPeriod.yearly => 'Resets on 1 January',
                    BudgetPeriod.custom => 'A fixed date range',
                  },
                  style: context.text.bodySmall,
                ),
                trailing: period == _period
                    ? Icon(Icons.check_rounded, color: context.colors.primary)
                    : null,
                onTap: () => Navigator.of(context).pop(period),
              ),
          ],
        ),
      ),
    );

    if (picked != null) setState(() => _period = picked);
  }

  Future<void> _delete(Budget budget) async {
    final confirmed = await AppFeedback.confirm(
      context,
      title: 'Delete budget?',
      message: 'Your transactions are not affected — only the limit and its '
          'alerts are removed.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    final done = await AppFeedback.runWithProgress(
      context,
      successMessage: 'Budget deleted',
      action: () async {
        await ref.read(budgetsControllerProvider.notifier).delete(budget.id);
        return true;
      },
    );

    if (done == true && mounted) context.pop();
  }
}

/// Where the first warning fires.
class _ThresholdSelector extends StatelessWidget {
  const _ThresholdSelector({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  static const List<int> _options = [50, 75, 80, 90, 100];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Warn me at', style: context.text.titleSmall),
        AppSpacing.gapXs,
        Text(
          'Finora notifies you when spending reaches this share of the budget.',
          style: context.text.bodySmall,
        ),
        AppSpacing.gapMd,
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final option in _options)
              ChoiceChip(
                label: Text('$option%'),
                selected: value == option,
                onSelected: (_) => onChanged(option),
              ),
          ],
        ),
      ],
    );
  }
}
