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
import '../../../shared/models/account.dart';
import '../../../shared/models/category.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/models/transaction_candidate.dart';
import '../../../shared/providers/account_providers.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/providers/transaction_providers.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/pickers.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/transaction_tile.dart';

/// Add or edit a transaction.
///
/// One screen for all three types, because the fields overlap almost entirely
/// and a type switch at the top is faster than three separate entry points. The
/// transfer case swaps the category picker for a destination account, which is
/// the only structural difference.
class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({
    super.key,
    this.transactionId,
    this.initialType,
  });

  /// Null when adding.
  final String? transactionId;
  final TransactionType? initialType;

  bool get isEditing => transactionId != null;

  @override
  ConsumerState<TransactionFormScreen> createState() =>
      _TransactionFormScreenState();
}

class _TransactionFormScreenState
    extends ConsumerState<TransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _notesController = TextEditingController();
  final _referenceController = TextEditingController();

  TransactionType _type = TransactionType.expense;
  Account? _account;
  Account? _toAccount;
  Category? _category;
  PaymentMethod? _paymentMethod;
  DateTime _date = DateTime.now();
  bool _isSubmitting = false;
  bool _isLoaded = false;
  List<DuplicateMatch> _duplicates = const [];
  bool _duplicatesDismissed = false;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType ?? TransactionType.expense;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  /// Fills the form from an existing transaction, once.
  void _hydrate(Transaction transaction) {
    if (_isLoaded) return;
    _isLoaded = true;

    _type = transaction.type;
    _amountController.text = transaction.amount.toEditableString();
    _merchantController.text = transaction.merchant ?? '';
    _descriptionController.text = transaction.description ?? '';
    _notesController.text = transaction.notes ?? '';
    _referenceController.text = transaction.referenceNumber ?? '';
    _paymentMethod = transaction.paymentMethod;
    _date = transaction.transactionDate;
    _account = transaction.account;
    _category = transaction.category;

    if (transaction.type.isTransfer) {
      // The edit screen always shows the outgoing leg, so "to" is the peer.
      _toAccount = transaction.transferPeerAccount;
      if (transaction.transferDirection == TransferDirection.incoming) {
        _account = transaction.transferPeerAccount;
        _toAccount = transaction.account;
      }
    }
  }

  void _applyDefaults() {
    if (_isLoaded) return;
    _isLoaded = true;
    _account = ref.read(defaultAccountProvider);
  }

  /// The amount is parsed in the selected account's currency, because one
  /// account holds exactly one currency and the database enforces the match.
  Money? get _amount {
    final String currency =
        _account?.currency ?? ref.read(currencyProvider);
    return Money.tryParse(_amountController.text, currency);
  }

  /// Looks for an existing transaction that resembles this one.
  ///
  /// Advisory only, and only when there is enough to compare: a warning is more
  /// useful than a silent duplicate, but blocking the save would be wrong — the
  /// user may genuinely have bought the same coffee twice.
  Future<void> _checkDuplicates() async {
    final amount = _amount;
    if (amount == null || amount.isZero || _type.isTransfer) {
      setState(() => _duplicates = const []);
      return;
    }

    try {
      final matches =
          await ref.read(transactionWriterProvider.notifier).findDuplicates(
                amount: amount,
                date: _date,
                merchant: _merchantController.text.trim().isEmpty
                    ? null
                    : _merchantController.text.trim(),
                accountId: _account?.id,
                excludeTransactionId: widget.transactionId,
              );
      if (mounted) {
        setState(() {
          _duplicates = matches;
          _duplicatesDismissed = false;
        });
      }
    } on Object {
      // A failed duplicate check must not block entry; the save path is
      // unaffected.
      if (mounted) setState(() => _duplicates = const []);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final account = _account;
    if (account == null) {
      AppFeedback.showValidation(context, 'Choose an account.');
      return;
    }

    final amount = _amount;
    if (amount == null || amount.isZero || amount.isNegative) {
      AppFeedback.showValidation(
        context,
        'Enter an amount greater than zero.',
      );
      return;
    }

    if (_type.isTransfer) {
      final error = Validators.transferAccounts(account.id, _toAccount?.id);
      if (error != null) {
        AppFeedback.showValidation(context, error);
        return;
      }
    }

    context.hideKeyboard();
    setState(() => _isSubmitting = true);

    final writer = ref.read(transactionWriterProvider.notifier);

    try {
      if (_type.isTransfer) {
        if (widget.isEditing) {
          final existing =
              await ref.read(transactionDetailProvider(widget.transactionId!).future);
          await writer.save(
            existing.copyWith(
              amount: amount,
              transactionDate: _date,
              description: _nullIfEmpty(_descriptionController.text),
              notes: _nullIfEmpty(_notesController.text),
              paymentMethod: _paymentMethod,
            ),
          );
        } else {
          await writer.createTransfer(
            fromAccountId: account.id,
            toAccountId: _toAccount!.id,
            amount: amount,
            date: _date,
            description: _nullIfEmpty(_descriptionController.text),
            notes: _nullIfEmpty(_notesController.text),
            paymentMethod: _paymentMethod,
          );
        }
      } else {
        final base = Transaction(
          id: widget.transactionId ?? '',
          userId: '',
          accountId: account.id,
          categoryId: _category?.id,
          type: _type,
          amount: amount,
          description: _nullIfEmpty(_descriptionController.text),
          merchant: _nullIfEmpty(_merchantController.text),
          paymentMethod: _paymentMethod,
          transactionDate: _date,
          notes: _nullIfEmpty(_notesController.text),
          referenceNumber: _nullIfEmpty(_referenceController.text),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        if (widget.isEditing) {
          final existing = await ref
              .read(transactionDetailProvider(widget.transactionId!).future);
          await writer.save(
            existing.copyWith(
              accountId: account.id,
              categoryId: _category?.id,
              type: _type,
              amount: amount,
              description: base.description,
              merchant: base.merchant,
              paymentMethod: _paymentMethod,
              transactionDate: _date,
              notes: base.notes,
              referenceNumber: base.referenceNumber,
            ),
          );
        } else {
          await writer.create(base);
        }
      }

      if (!mounted) return;
      AppFeedback.showSuccess(
        context,
        widget.isEditing ? 'Transaction updated' : 'Transaction saved',
      );
      context.pop();
    } on Object catch (error) {
      if (mounted) AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  static String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    // Editing loads the existing row first; adding starts from the defaults.
    if (widget.isEditing) {
      final existing = ref.watch(transactionDetailProvider(widget.transactionId!));
      return existing.view(
        (transaction) {
          _hydrate(transaction);
          return _buildForm(context);
        },
        loading: const Scaffold(body: LoadingView()),
        onRetry: () =>
            ref.invalidate(transactionDetailProvider(widget.transactionId!)),
      );
    }

    _applyDefaults();
    return _buildForm(context);
  }

  Widget _buildForm(BuildContext context) {
    final accounts = ref.watch(activeAccountsProvider);
    final categories = ref.watch(
      categoriesByKindProvider(
        _type == TransactionType.income
            ? CategoryKind.income
            : CategoryKind.expense,
      ),
    );
    final String currency =
        _account?.currency ?? ref.watch(currencyProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEditing ? 'Edit transaction' : 'Add transaction',
        ),
        actions: [
          if (!_isSubmitting)
            TextButton(
              onPressed: _submit,
              child: const Text('Save'),
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.page),
            children: [
              // Editing a transfer cannot change its shape: converting a
              // transfer into an expense would leave one orphaned leg.
              if (!widget.isEditing || !_type.isTransfer)
                SegmentedTypeSelector<TransactionType>(
                  options: widget.isEditing
                      ? [TransactionType.expense, TransactionType.income]
                      : TransactionType.values,
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
                    // A category belongs to one kind, so it cannot survive a
                    // switch between income and expense.
                    _category = null;
                    _duplicates = const [];
                  }),
                ),
              AppSpacing.gapXl,

              AmountField(
                controller: _amountController,
                currency: currency,
                autofocus: !widget.isEditing,
                validator: (value) =>
                    Validators.amount(value, currency: currency),
                onChanged: (_) => setState(() {}),
              ),
              AppSpacing.gapMd,
              AmountQuickActions(
                controller: _amountController,
                currency: currency,
                onChanged: (_) => setState(() {}),
              ),
              AppSpacing.gapXl,

              if (_duplicates.isNotEmpty && !_duplicatesDismissed) ...[
                _DuplicateWarning(
                  matches: _duplicates,
                  onDismiss: () => setState(() => _duplicatesDismissed = true),
                ),
                AppSpacing.gapXl,
              ],

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
                  if (picked != null) {
                    setState(() => _account = picked);
                    _checkDuplicates();
                  }
                },
              ),
              AppSpacing.gapLg,

              if (_type.isTransfer)
                PickerField(
                  label: 'To account',
                  isRequired: true,
                  value: _toAccount?.name,
                  enabled: !widget.isEditing,
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

              if (!_type.isTransfer) ...[
                TextFormField(
                  controller: _merchantController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  onEditingComplete: _checkDuplicates,
                  decoration: InputDecoration(
                    labelText: _type == TransactionType.income
                        ? 'Source'
                        : 'Merchant',
                    hintText: _type == TransactionType.income
                        ? 'Employer, client…'
                        : 'Where did you spend?',
                    prefixIcon: const Icon(Icons.storefront_outlined),
                  ),
                ),
                AppSpacing.gapLg,
              ],

              TextFormField(
                controller: _descriptionController,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'What was it for?',
                  prefixIcon: Icon(Icons.notes_rounded),
                  counterText: '',
                ),
              ),
              AppSpacing.gapLg,

              Row(
                children: [
                  Expanded(
                    child: PickerField(
                      label: 'Date',
                      value: DateDisplay.dayMonthYear(_date),
                      leading: const Icon(Icons.event_outlined, size: 20),
                      onTap: () async {
                        final picked =
                            await DateTimePickers.pickTransactionDate(
                          context,
                          initial: _date,
                        );
                        if (picked != null) {
                          setState(() {
                            _date = DateTime(
                              picked.year,
                              picked.month,
                              picked.day,
                              _date.hour,
                              _date.minute,
                            );
                          });
                          _checkDuplicates();
                        }
                      },
                    ),
                  ),
                  AppSpacing.hGapMd,
                  Expanded(
                    child: PickerField(
                      label: 'Time',
                      value: DateDisplay.time(_date),
                      leading:
                          const Icon(Icons.schedule_outlined, size: 20),
                      onTap: () async {
                        final picked = await DateTimePickers.pickTime(
                          context,
                          initial: _date,
                        );
                        if (picked != null) {
                          setState(() {
                            _date = DateTime(
                              _date.year,
                              _date.month,
                              _date.day,
                              picked.hour,
                              picked.minute,
                            );
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
              AppSpacing.gapLg,

              PickerField(
                label: 'Payment method',
                value: _paymentMethod?.label,
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

              _MoreDetails(
                notesController: _notesController,
                referenceController: _referenceController,
                showReference: !_type.isTransfer,
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
                        widget.isEditing
                            ? 'Save changes'
                            : 'Save ${_type.label.toLowerCase()}',
                      ),
              ),
              if (widget.isEditing) ...[
                AppSpacing.gapLg,
                OutlinedButton.icon(
                  onPressed: _isSubmitting ? null : () => _delete(context, ref),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: context.palette.danger,
                  ),
                  label: Text(
                    'Delete transaction',
                    style: TextStyle(color: context.palette.danger),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: context.palette.danger.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
              AppSpacing.gapXxl,
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final existing = await ref.read(transactionDetailProvider(widget.transactionId!).future);
    if (!context.mounted) return;

    final confirmed = await AppFeedback.confirm(
      context,
      title: 'Delete transaction?',
      message: existing.type.isTransfer
          ? 'Both sides of this transfer will be removed and both account balances adjusted.'
          : 'This transaction will be removed and your account balance adjusted.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final done = await AppFeedback.runWithProgress(
      context,
      progressMessage: 'Deleting…',
      successMessage: 'Transaction deleted',
      action: () async {
        await ref
            .read(transactionListControllerProvider.notifier)
            .delete(existing);
        return true;
      },
    );

    if (done == true && context.mounted) context.pop();
  }
}

/// Collapsible extras, so the common path stays short.
class _MoreDetails extends StatefulWidget {
  const _MoreDetails({
    required this.notesController,
    required this.referenceController,
    required this.showReference,
  });

  final TextEditingController notesController;
  final TextEditingController referenceController;
  final bool showReference;

  @override
  State<_MoreDetails> createState() => _MoreDetailsState();
}

class _MoreDetailsState extends State<_MoreDetails> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // Already-filled extras should be visible, not hidden behind a toggle.
    _expanded = widget.notesController.text.isNotEmpty ||
        widget.referenceController.text.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: AppRadius.smAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                Text('More details', style: context.text.titleSmall),
                AppSpacing.hGapSm,
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: context.palette.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          AppSpacing.gapMd,
          TextFormField(
            controller: widget.notesController,
            maxLines: 3,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notes',
              alignLabelWithHint: true,
            ),
          ),
          if (widget.showReference) ...[
            AppSpacing.gapLg,
            TextFormField(
              controller: widget.referenceController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Reference number',
                hintText: 'Receipt or transaction reference',
                prefixIcon: Icon(Icons.tag_rounded),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// Warns that a similar transaction already exists.
class _DuplicateWarning extends StatelessWidget {
  const _DuplicateWarning({required this.matches, required this.onDismiss});

  final List<DuplicateMatch> matches;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderColor: context.palette.warning.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.content_copy_outlined,
                size: 18,
                color: context.palette.warning,
              ),
              AppSpacing.hGapSm,
              Expanded(
                child: Text(
                  matches.length == 1
                      ? 'Possible duplicate'
                      : '${matches.length} possible duplicates',
                  style: context.text.titleSmall
                      ?.copyWith(color: context.palette.warning),
                ),
              ),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          AppSpacing.gapSm,
          Text(
            'You already have a similar transaction. You can still save this '
            'one if it is a separate purchase.',
            style: context.text.bodySmall,
          ),
          AppSpacing.gapMd,
          for (final match in matches.take(2)) ...[
            TransactionMiniTile(
              transaction: match.existing,
              onTap: () =>
                  context.push(AppRoutes.transactionDetail(match.existing.id)),
            ),
            if (match.reasons.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.page,
                  bottom: AppSpacing.sm,
                ),
                child: Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    for (final reason in match.reasons)
                      AppChipLabel(label: reason, dense: true),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
