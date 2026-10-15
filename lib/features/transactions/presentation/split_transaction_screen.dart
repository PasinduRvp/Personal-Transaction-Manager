import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/models/category.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/providers/account_providers.dart';
import '../../../shared/providers/transaction_providers.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/pickers.dart';
import '../../../shared/widgets/state_views.dart';

/// Splits one transaction across several categories.
///
/// The split lines must add up to the parent amount exactly. That is checked
/// here for immediate feedback, and again by a deferred database constraint, so
/// a set that does not reconcile cannot be committed by any route — including a
/// direct API call.
class SplitTransactionScreen extends ConsumerStatefulWidget {
  const SplitTransactionScreen({super.key, required this.transactionId});

  final String transactionId;

  @override
  ConsumerState<SplitTransactionScreen> createState() =>
      _SplitTransactionScreenState();
}

class _SplitTransactionScreenState
    extends ConsumerState<SplitTransactionScreen> {
  final List<_SplitDraft> _drafts = [];
  bool _isLoaded = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  void _hydrate(Transaction transaction) {
    if (_isLoaded) return;
    _isLoaded = true;

    if (transaction.splits.isEmpty) {
      // Start with two even halves: splitting into one line is meaningless, and
      // an even split is the most common starting point.
      final halves = transaction.amount.splitEvenly(2);
      _drafts.addAll([
        _SplitDraft.fromValues(
          amount: halves[0],
          category: transaction.category,
        ),
        _SplitDraft.fromValues(amount: halves[1]),
      ]);
    } else {
      for (final split in transaction.splits) {
        _drafts.add(_SplitDraft.fromValues(
          amount: split.amount,
          category: split.category,
          description: split.description,
        ));
      }
    }
  }

  Money _total(String currency) {
    var total = Money.zero(currency);
    for (final draft in _drafts) {
      total += draft.amount(currency) ?? Money.zero(currency);
    }
    return total;
  }

  void _addLine(Transaction transaction) {
    setState(() {
      final remaining = transaction.amount - _total(transaction.currency);
      _drafts.add(
        _SplitDraft.fromValues(
          amount: remaining.isPositive ? remaining : null,
        ),
      );
    });
  }

  /// Puts the unallocated remainder on one line, so the user does not have to do
  /// the arithmetic themselves.
  void _balanceTo(int index, Transaction transaction) {
    final currency = transaction.currency;
    var others = Money.zero(currency);
    for (var i = 0; i < _drafts.length; i++) {
      if (i == index) continue;
      others += _drafts[i].amount(currency) ?? Money.zero(currency);
    }
    final remainder = transaction.amount - others;
    if (remainder.isNegative || remainder.isZero) {
      AppFeedback.showValidation(
        context,
        'The other lines already account for the full amount.',
      );
      return;
    }
    setState(() => _drafts[index].setAmount(remainder));
  }

  Future<void> _save(Transaction transaction) async {
    final currency = transaction.currency;
    final amounts = <Money>[];

    for (final draft in _drafts) {
      final amount = draft.amount(currency);
      if (amount == null || amount.isZero) {
        AppFeedback.showValidation(
          context,
          'Every split line needs an amount greater than zero.',
        );
        return;
      }
      amounts.add(amount);
    }

    final error = Validators.splitTotal(transaction.amount, amounts);
    if (error != null) {
      AppFeedback.showValidation(context, error);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref.read(transactionWriterProvider.notifier).replaceSplits(
            transaction: transaction,
            splits: [
              for (var i = 0; i < _drafts.length; i++)
                TransactionSplit(
                  id: '',
                  transactionId: transaction.id,
                  amount: amounts[i],
                  categoryId: _drafts[i].category?.id,
                  description: _drafts[i].descriptionOrNull,
                  sortOrder: i,
                ),
            ],
          );

      if (!mounted) return;
      AppFeedback.showSuccess(context, 'Split saved');
      context.pop();
    } on Object catch (error) {
      if (mounted) AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _removeSplit(Transaction transaction) async {
    final confirmed = await AppFeedback.confirm(
      context,
      title: 'Remove the split?',
      message: 'The transaction goes back to a single category. The amount does '
          'not change.',
      confirmLabel: 'Remove split',
    );
    if (!confirmed || !mounted) return;

    final done = await AppFeedback.runWithProgress(
      context,
      successMessage: 'Split removed',
      action: () async {
        await ref.read(transactionWriterProvider.notifier).replaceSplits(
              transaction: transaction,
              splits: const [],
            );
        return true;
      },
    );

    if (done == true && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final transaction = ref.watch(transactionDetailProvider(widget.transactionId));

    return transaction.view(
      (data) {
        _hydrate(data);
        return _buildScaffold(context, data);
      },
      loading: const Scaffold(body: LoadingView()),
      onRetry: () =>
          ref.invalidate(transactionDetailProvider(widget.transactionId)),
    );
  }

  Widget _buildScaffold(BuildContext context, Transaction transaction) {
    final currency = transaction.currency;
    final allocated = _total(currency);
    final remaining = transaction.amount - allocated;
    final isBalanced = remaining.isZero;
    final categories =
        ref.watch(categoriesByKindProvider(
      transaction.type == TransactionType.income
          ? CategoryKind.income
          : CategoryKind.expense,
    ));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Split transaction'),
        actions: [
          if (transaction.isSplit)
            IconButton(
              onPressed: () => _removeSplit(transaction),
              icon: const Icon(Icons.layers_clear_outlined),
              tooltip: 'Remove split',
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.page),
                children: [
                  AppCard(
                    child: Row(
                      children: [
                        IconBadge(
                          icon: transaction.icon,
                          color: transaction.category?.color ??
                              context.palette.textSecondary,
                        ),
                        AppSpacing.hGapLg,
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                transaction.title,
                                style: context.text.titleSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Total to allocate',
                                style: context.text.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        MoneyText(transaction.amount, size: MoneySize.large),
                      ],
                    ),
                  ),
                  AppSpacing.gapLg,

                  for (var i = 0; i < _drafts.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _SplitLineCard(
                        index: i,
                        draft: _drafts[i],
                        currency: currency,
                        categories: categories,
                        canRemove: _drafts.length > 2,
                        onChanged: () => setState(() {}),
                        onRemove: () => setState(() {
                          _drafts.removeAt(i).dispose();
                        }),
                        onBalance: () => _balanceTo(i, transaction),
                      ),
                    ),

                  OutlinedButton.icon(
                    onPressed: () => _addLine(transaction),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add another line'),
                  ),
                  AppSpacing.gapXxl,
                ],
              ),
            ),

            _SplitFooter(
              allocated: allocated,
              remaining: remaining,
              isBalanced: isBalanced,
              isSubmitting: _isSubmitting,
              onSave: () => _save(transaction),
              onSplitEvenly: () => setState(() {
                final shares = transaction.amount.splitEvenly(_drafts.length);
                for (var i = 0; i < _drafts.length; i++) {
                  _drafts[i].setAmount(shares[i]);
                }
              }),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mutable state for one split line.
class _SplitDraft {
  _SplitDraft.fromValues({Money? amount, this.category, String? description})
      : amountController = TextEditingController(
          text: amount?.toEditableString() ?? '',
        ),
        descriptionController =
            TextEditingController(text: description ?? '');

  final TextEditingController amountController;
  final TextEditingController descriptionController;
  Category? category;

  Money? amount(String currency) =>
      Money.tryParse(amountController.text, currency);

  String? get descriptionOrNull {
    final text = descriptionController.text.trim();
    return text.isEmpty ? null : text;
  }

  void setAmount(Money value) {
    amountController.text = value.toEditableString();
  }

  void dispose() {
    amountController.dispose();
    descriptionController.dispose();
  }
}

class _SplitLineCard extends StatelessWidget {
  const _SplitLineCard({
    required this.index,
    required this.draft,
    required this.currency,
    required this.categories,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
    required this.onBalance,
  });

  final int index;
  final _SplitDraft draft;
  final String currency;
  final List<Category> categories;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final VoidCallback onBalance;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Line ${index + 1}', style: context.text.labelMedium),
              const Spacer(),
              TextButton(
                onPressed: onBalance,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Use remainder'),
              ),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Remove line',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          AppSpacing.gapSm,
          AmountField(
            controller: draft.amountController,
            currency: currency,
            label: 'Amount',
            compact: true,
            onChanged: (_) => onChanged(),
          ),
          AppSpacing.gapMd,
          PickerField(
            label: 'Category',
            value: draft.category?.name,
            leading: draft.category == null
                ? null
                : Icon(
                    draft.category!.icon,
                    size: 18,
                    color: draft.category!.color,
                  ),
            onTap: () async {
              final picked = await CategoryPicker.show(
                context,
                categories: categories,
                selectedId: draft.category?.id,
                allowNone: true,
              );
              if (picked != null) {
                draft.category =
                    CategoryPicker.isNone(picked) ? null : picked;
                onChanged();
              }
            },
          ),
          AppSpacing.gapMd,
          TextField(
            controller: draft.descriptionController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Description',
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// The running allocation status and the save button.
class _SplitFooter extends StatelessWidget {
  const _SplitFooter({
    required this.allocated,
    required this.remaining,
    required this.isBalanced,
    required this.isSubmitting,
    required this.onSave,
    required this.onSplitEvenly,
  });

  final Money allocated;
  final Money remaining;
  final bool isBalanced;
  final bool isSubmitting;
  final VoidCallback onSave;
  final VoidCallback onSplitEvenly;

  @override
  Widget build(BuildContext context) {
    final color = isBalanced
        ? context.palette.income
        : remaining.isNegative
            ? context.palette.danger
            : context.palette.warning;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.colors.outline)),
      ),
      padding: const EdgeInsets.all(AppSpacing.page),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  isBalanced
                      ? Icons.check_circle_outline_rounded
                      : Icons.info_outline_rounded,
                  size: 18,
                  color: color,
                ),
                AppSpacing.hGapSm,
                Expanded(
                  child: Text(
                    isBalanced
                        ? 'Splits add up to the total'
                        : remaining.isNegative
                            ? 'Over by ${remaining.abs.format()}'
                            : '${remaining.format()} left to allocate',
                    style: context.text.titleSmall?.copyWith(color: color),
                  ),
                ),
                TextButton(
                  onPressed: onSplitEvenly,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Split evenly'),
                ),
              ],
            ),
            AppSpacing.gapMd,
            FilledButton(
              // Disabled until it balances: the database would reject an
              // unbalanced set anyway, and a button that fails is worse than a
              // button that waits.
              onPressed: isBalanced && !isSubmitting ? onSave : null,
              child: isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save split'),
            ),
          ],
        ),
      ),
    );
  }
}
