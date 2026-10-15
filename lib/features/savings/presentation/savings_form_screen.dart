import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/models/account.dart';
import '../../../shared/models/savings_goal.dart';
import '../../../shared/providers/account_providers.dart';
import '../../../shared/providers/planning_providers.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/pickers.dart';
import '../../../shared/widgets/state_views.dart';

/// Create or edit a savings goal.
class SavingsFormScreen extends ConsumerStatefulWidget {
  const SavingsFormScreen({super.key, this.goalId});

  final String? goalId;

  bool get isEditing => goalId != null;

  @override
  ConsumerState<SavingsFormScreen> createState() => _SavingsFormScreenState();
}

class _SavingsFormScreenState extends ConsumerState<SavingsFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _targetController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime? _targetDate;
  Account? _account;
  String? _iconName;
  Color? _color;
  bool _isLoaded = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _hydrate(SavingsGoal goal) {
    if (_isLoaded) return;
    _isLoaded = true;

    _nameController.text = goal.name;
    _targetController.text = goal.targetAmount.toEditableString();
    _notesController.text = goal.notes ?? '';
    _targetDate = goal.targetDate;
    _iconName = goal.iconName;
    _color = AppColors.tryParseHex(goal.colorHex);
    _account = ref.read(accountByIdProvider(goal.accountId));
  }

  Future<void> _submit(SavingsGoal? existing) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final String currency = existing?.currency ?? ref.read(currencyProvider);
    final target = Money.tryParse(_targetController.text, currency);
    if (target == null || target.isZero) {
      AppFeedback.showValidation(context, 'Enter a target amount.');
      return;
    }

    // Lowering a target below what is already saved would make the goal
    // permanently over-funded and its progress meaningless.
    if (existing != null && target < existing.currentAmount) {
      AppFeedback.showValidation(
        context,
        'The target must be at least '
        '${existing.currentAmount.format()}, which you have already saved.',
      );
      return;
    }

    context.hideKeyboard();
    setState(() => _isSubmitting = true);
    final controller = ref.read(savingsControllerProvider.notifier);

    try {
      if (existing != null) {
        await controller.save(
          existing.copyWith(
            name: _nameController.text.trim(),
            targetAmount: target,
            targetDate: _targetDate,
            accountId: _account?.id,
            iconName: _iconName,
            colorHex: _color == null ? null : AppColors.toHex(_color!),
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          ),
        );
      } else {
        await controller.create(
          SavingsGoal(
            id: '',
            userId: '',
            name: _nameController.text.trim(),
            targetAmount: target,
            currentAmount: Money.zero(currency),
            targetDate: _targetDate,
            accountId: _account?.id,
            iconName: _iconName,
            colorHex: _color == null ? null : AppColors.toHex(_color!),
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
        existing != null ? 'Goal updated' : 'Goal created',
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
      final goal = ref.watch(savingsGoalByIdProvider(widget.goalId!));
      if (goal == null) {
        final goals = ref.watch(savingsControllerProvider);
        return goals.view(
          (_) => const Scaffold(
            body: EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Goal not found',
              message: 'It may have been deleted.',
            ),
          ),
          loading: const Scaffold(body: LoadingView()),
        );
      }
      _hydrate(goal);
      return _buildForm(context, goal);
    }

    return _buildForm(context, null);
  }

  Widget _buildForm(BuildContext context, SavingsGoal? existing) {
    final String currency = existing?.currency ?? ref.watch(currencyProvider);
    final accounts = ref.watch(activeAccountsProvider);
    final previewColor = _color ?? context.colors.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text(existing != null ? 'Edit goal' : 'New savings goal'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.page),
            children: [
              Center(
                child: IconBadge(
                  icon: SavingsGoal.iconFor(_iconName),
                  color: previewColor,
                  size: 64,
                ),
              ),
              AppSpacing.gapXl,

              TextFormField(
                controller: _nameController,
                autofocus: existing == null,
                textCapitalization: TextCapitalization.words,
                validator: (value) =>
                    Validators.required(value, field: 'Goal name'),
                decoration: const InputDecoration(
                  labelText: 'Goal name *',
                  hintText: 'New laptop, emergency fund…',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
              ),
              AppSpacing.gapLg,

              AmountField(
                controller: _targetController,
                currency: currency,
                label: 'Target amount',
                validator: (value) =>
                    Validators.amount(value, currency: currency),
              ),
              AppSpacing.gapLg,

              PickerField(
                label: 'Target date',
                value: _targetDate == null
                    ? null
                    : DateDisplay.dayMonthYear(_targetDate!),
                placeholder: 'Optional',
                leading: const Icon(Icons.event_outlined, size: 20),
                trailing: _targetDate == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() => _targetDate = null),
                        tooltip: 'Clear',
                      ),
                onTap: () async {
                  final picked = await DateTimePickers.pickFutureDate(
                    context,
                    initial: _targetDate ??
                        DateTime.now().add(const Duration(days: 180)),
                    helpText: 'Target date',
                  );
                  if (picked != null) setState(() => _targetDate = picked);
                },
              ),
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.xs,
                  left: AppSpacing.md,
                ),
                child: Text(
                  'With a target date, Finora works out how much to set aside '
                  'each month.',
                  style: context.text.bodySmall,
                ),
              ),
              AppSpacing.gapLg,

              PickerField(
                label: 'Held in account',
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
                trailing: _account == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() => _account = null),
                        tooltip: 'Clear',
                      ),
                onTap: () async {
                  final picked = await AccountPicker.show(
                    context,
                    accounts: accounts,
                    selectedId: _account?.id,
                    title: 'Where is this money kept?',
                  );
                  if (picked != null) setState(() => _account = picked);
                },
              ),
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.xs,
                  left: AppSpacing.md,
                ),
                child: Text(
                  'Linking an account lets contributions be recorded as real '
                  'transfers.',
                  style: context.text.bodySmall,
                ),
              ),
              AppSpacing.gapLg,

              Row(
                children: [
                  Expanded(
                    child: PickerField(
                      label: 'Icon',
                      value: _iconName ?? 'Default',
                      onTap: () async {
                        final picked = await IconPicker.show(
                          context,
                          selectedName: _iconName,
                          names: SavingsGoal.iconNames,
                        );
                        if (picked != null) {
                          setState(() => _iconName = picked);
                        }
                      },
                    ),
                  ),
                  AppSpacing.hGapMd,
                  Expanded(
                    child: PickerField(
                      label: 'Colour',
                      value: _color == null ? 'Default' : 'Custom',
                      leading: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: previewColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      onTap: () async {
                        final picked = await ColorPicker.show(
                          context,
                          selected: _color,
                        );
                        if (picked != null) setState(() => _color = picked);
                      },
                    ),
                  ),
                ],
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
                    : Text(existing != null ? 'Save changes' : 'Create goal'),
              ),
              AppSpacing.gapXxl,
            ],
          ),
        ),
      ),
    );
  }
}
