import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
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
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/pickers.dart';
import '../../../shared/widgets/state_views.dart';

/// One savings goal: progress, contribution history, and the actions on it.
class SavingsDetailScreen extends ConsumerWidget {
  const SavingsDetailScreen({super.key, required this.goalId});

  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = ref.watch(savingsGoalByIdProvider(goalId));
    final goals = ref.watch(savingsControllerProvider);

    if (goal == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Savings goal')),
        body: goals.view(
          (_) => const EmptyState(
            icon: Icons.search_off_rounded,
            title: 'Goal not found',
            message: 'It may have been deleted.',
          ),
          loading: const LoadingView(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(goal.name),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.savingsEdit(goal.id)),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
          ),
          _GoalMenu(goal: goal),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(savingsControllerProvider.notifier).refresh(),
        child: _Body(goal: goal),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.goal});

  final SavingsGoal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contributions = ref.watch(savingsContributionsProvider(goal.id));
    final obscure = ref.watch(hideAmountsProvider);
    final required = goal.requiredMonthlyContribution;
    final days = goal.daysRemaining;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              IconBadge(icon: goal.icon, color: goal.color, size: 60),
              AppSpacing.gapLg,
              MoneyText(
                goal.currentAmount,
                size: MoneySize.hero,
                obscured: obscure,
              ),
              AppSpacing.gapXs,
              Text(
                'of ${goal.targetAmount.format()}',
                style: context.text.bodyMedium,
              ),
              AppSpacing.gapLg,
              ProgressMeter(
                fraction: goal.progressFraction,
                color: goal.color,
                height: 12,
              ),
              AppSpacing.gapMd,
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${goal.progressPercent.toStringAsFixed(goal.progressPercent >= 10 ? 0 : 1)}% saved',
                    style: context.text.titleSmall,
                  ),
                  Text(
                    goal.isReached
                        ? 'Target reached'
                        : '${goal.remaining.format()} to go',
                    style: context.text.bodyMedium?.copyWith(
                      color: goal.isReached ? context.palette.income : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        AppSpacing.gapLg,

        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => ContributionSheet.show(
                  context,
                  goal: goal,
                  isWithdrawal: false,
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add money'),
              ),
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: OutlinedButton.icon(
                onPressed: goal.currentAmount.isZero
                    ? null
                    : () => ContributionSheet.show(
                          context,
                          goal: goal,
                          isWithdrawal: true,
                        ),
                icon: const Icon(Icons.remove_rounded, size: 18),
                label: const Text('Withdraw'),
              ),
            ),
          ],
        ),
        AppSpacing.gapLg,

        AppCard(
          child: Column(
            children: [
              DetailRow(
                label: 'Target amount',
                icon: Icons.flag_outlined,
                valueWidget: MoneyText(
                  goal.targetAmount,
                  size: MoneySize.row,
                  obscured: obscure,
                ),
              ),
              if (goal.targetDate != null) ...[
                const Divider(height: 1),
                DetailRow(
                  label: 'Target date',
                  icon: Icons.event_outlined,
                  value: DateDisplay.dayMonthYear(goal.targetDate!),
                ),
                const Divider(height: 1),
                DetailRow(
                  label: 'Time left',
                  icon: Icons.schedule_outlined,
                  value: days == null
                      ? '—'
                      : days < 0
                          ? '${-days} days overdue'
                          : '$days day${days == 1 ? '' : 's'}',
                ),
              ],
              if (required != null) ...[
                const Divider(height: 1),
                DetailRow(
                  label: 'Needed per month',
                  icon: Icons.trending_up_rounded,
                  valueWidget: MoneyText(required, size: MoneySize.row),
                ),
              ],
              if (goal.accountId != null) ...[
                const Divider(height: 1),
                _LinkedAccountRow(accountId: goal.accountId!),
              ],
            ],
          ),
        ),

        if (goal.notes != null) ...[
          AppSpacing.gapLg,
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notes', style: context.text.labelMedium),
                AppSpacing.gapXs,
                Text(goal.notes!, style: context.text.bodyMedium),
              ],
            ),
          ),
        ],

        AppSpacing.gapXl,
        Text('History', style: context.text.titleMedium),
        AppSpacing.gapMd,
        contributions.view(
          (data) => data.isEmpty
              ? const EmptyState(
                  icon: Icons.history_rounded,
                  title: 'No contributions yet',
                  message: 'Add money to start filling this goal.',
                  compact: true,
                )
              : AppCard(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Column(
                    children: [
                      for (var i = 0; i < data.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, indent: AppSpacing.lg),
                        _ContributionRow(contribution: data[i]),
                      ],
                    ],
                  ),
                ),
          loading: const CardSkeleton(height: 140),
          onRetry: () =>
              ref.invalidate(savingsContributionsProvider(goal.id)),
        ),
        AppSpacing.gapXxl,
      ],
    );
  }
}

class _LinkedAccountRow extends ConsumerWidget {
  const _LinkedAccountRow({required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountByIdProvider(accountId));
    return DetailRow(
      label: 'Held in',
      icon: Icons.account_balance_wallet_outlined,
      value: account?.name ?? 'Account removed',
      onTap: account == null
          ? null
          : () => context.push(AppRoutes.accountDetail(accountId)),
    );
  }
}

class _ContributionRow extends ConsumerWidget {
  const _ContributionRow({required this.contribution});

  final SavingsContribution contribution;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWithdrawal = contribution.isWithdrawal;

    return ListTile(
      leading: IconBadge(
        icon: isWithdrawal
            ? Icons.arrow_upward_rounded
            : Icons.arrow_downward_rounded,
        color: isWithdrawal ? context.palette.expense : context.palette.income,
        size: 34,
      ),
      title: Text(
        isWithdrawal ? 'Withdrawal' : 'Contribution',
        style: context.text.titleSmall,
      ),
      subtitle: Text(
        [
          DateDisplay.relative(contribution.occurredOn),
          if (contribution.note != null) contribution.note!,
        ].join(' · '),
        style: context.text.bodySmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: MoneyText(
        contribution.amount.abs,
        size: MoneySize.row,
        color: isWithdrawal
            ? context.palette.expense
            : context.palette.income,
      ),
    );
  }
}

/// Adds to or withdraws from a goal.
///
/// The optional "move money from" account makes the contribution a real transfer
/// as well, so the goal total and the account balances cannot disagree.
class ContributionSheet extends ConsumerStatefulWidget {
  const ContributionSheet({
    super.key,
    required this.goal,
    required this.isWithdrawal,
  });

  final SavingsGoal goal;
  final bool isWithdrawal;

  static Future<void> show(
    BuildContext context, {
    required SavingsGoal goal,
    required bool isWithdrawal,
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
        child: ContributionSheet(goal: goal, isWithdrawal: isWithdrawal),
      ),
    );
  }

  @override
  ConsumerState<ContributionSheet> createState() => _ContributionSheetState();
}

class _ContributionSheetState extends ConsumerState<ContributionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  Account? _account;
  DateTime _date = DateTime.now();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final currency = widget.goal.currency;
    final amount = Money.tryParse(_amountController.text, currency);
    if (amount == null || amount.isZero) {
      AppFeedback.showValidation(context, 'Enter an amount.');
      return;
    }

    if (widget.isWithdrawal && amount > widget.goal.currentAmount) {
      AppFeedback.showValidation(
        context,
        'You can withdraw at most '
        '${widget.goal.currentAmount.format()} from this goal.',
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final controller = ref.read(savingsControllerProvider.notifier);
    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();

    try {
      if (widget.isWithdrawal) {
        await controller.withdraw(
          goal: widget.goal,
          amount: amount,
          occurredOn: _date,
          note: note,
          toAccountId: _account?.id,
        );
      } else {
        await controller.contribute(
          goal: widget.goal,
          amount: amount,
          occurredOn: _date,
          note: note,
          fromAccountId: _account?.id,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      AppFeedback.showSuccess(
        context,
        widget.isWithdrawal ? 'Withdrawal recorded' : 'Contribution added',
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
    final currency = widget.goal.currency;
    final linkedAccountId = widget.goal.accountId;

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
                widget.isWithdrawal
                    ? 'Withdraw from ${widget.goal.name}'
                    : 'Add to ${widget.goal.name}',
                style: context.text.titleLarge,
              ),
              AppSpacing.gapSm,
              Text(
                widget.isWithdrawal
                    ? 'Currently holding ${widget.goal.currentAmount.format()}'
                    : '${widget.goal.remaining.format()} left to reach your '
                        'target',
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
              AppSpacing.gapMd,
              AmountQuickActions(
                controller: _amountController,
                currency: currency,
              ),
              AppSpacing.gapXl,

              PickerField(
                label: widget.isWithdrawal ? 'Move money to' : 'Take money from',
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
                    excludeId: linkedAccountId,
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
                  linkedAccountId == null
                      ? 'This goal has no linked account, so no transfer will '
                          'be recorded.'
                      : 'Choosing an account also records a transfer, keeping '
                          'your balances accurate.',
                  style: context.text.bodySmall,
                ),
              ),
              AppSpacing.gapLg,

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
                    : Text(
                        widget.isWithdrawal ? 'Withdraw' : 'Add contribution',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalMenu extends ConsumerWidget {
  const _GoalMenu({required this.goal});

  final SavingsGoal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (value) async {
        switch (value) {
          case 'complete':
            await AppFeedback.runWithProgress(
              context,
              successMessage: 'Goal marked complete',
              action: () => ref
                  .read(savingsControllerProvider.notifier)
                  .markComplete(goal.id),
            );
          case 'archive':
            await _archive(context, ref);
          case 'delete':
            await _delete(context, ref);
        }
      },
      itemBuilder: (context) => [
        if (!goal.isCompleted)
          const PopupMenuItem(
            value: 'complete',
            child: ListTile(
              leading: Icon(Icons.check_circle_outline_rounded),
              title: Text('Mark complete'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        PopupMenuItem(
          value: 'archive',
          child: ListTile(
            leading: Icon(
              goal.isArchived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
            ),
            title: Text(goal.isArchived ? 'Restore' : 'Archive'),
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

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final archiving = !goal.isArchived;
    final done = await AppFeedback.runWithProgress(
      context,
      successMessage: archiving ? 'Goal archived' : 'Goal restored',
      action: () async {
        await ref
            .read(savingsControllerProvider.notifier)
            .setArchived(goal.id, archived: archiving);
        return true;
      },
    );
    if (done == true && archiving && context.mounted) context.pop();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await AppFeedback.confirm(
      context,
      title: 'Delete goal?',
      message: 'The goal and its contribution history will be removed.',
      confirmLabel: 'Delete',
      isDestructive: true,
      consequences: const [
        'Any transfers you recorded stay in your transactions — that money '
            'really did move between accounts.',
      ],
    );
    if (!confirmed || !context.mounted) return;

    final done = await AppFeedback.runWithProgress(
      context,
      successMessage: 'Goal deleted',
      action: () async {
        await ref.read(savingsControllerProvider.notifier).delete(goal.id);
        return true;
      },
    );

    if (done == true && context.mounted) context.pop();
  }
}
