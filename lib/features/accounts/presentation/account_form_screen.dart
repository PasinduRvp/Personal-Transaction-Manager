import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/currencies.dart';
import '../../../core/constants/enums.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/models/account.dart';
import '../../../shared/providers/account_providers.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/providers/repository_providers.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/pickers.dart';
import '../../../shared/widgets/state_views.dart';

/// Create or edit an account.
class AccountFormScreen extends ConsumerStatefulWidget {
  const AccountFormScreen({super.key, this.accountId});

  final String? accountId;

  bool get isEditing => accountId != null;

  @override
  ConsumerState<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends ConsumerState<AccountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _institutionController = TextEditingController();
  final _last4Controller = TextEditingController();
  final _balanceController = TextEditingController();
  final _creditLimitController = TextEditingController();

  AccountType _type = AccountType.bank;
  String _currency = Currencies.fallback.code;
  String? _iconName;
  Color? _color;
  bool _isActive = true;
  bool _isLoaded = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _institutionController.dispose();
    _last4Controller.dispose();
    _balanceController.dispose();
    _creditLimitController.dispose();
    super.dispose();
  }

  void _hydrate(Account account) {
    if (_isLoaded) return;
    _isLoaded = true;

    _nameController.text = account.name;
    _institutionController.text = account.institutionName ?? '';
    _last4Controller.text = account.accountNumberLast4 ?? '';
    _balanceController.text = account.initialBalance.toEditableString();
    _creditLimitController.text = account.creditLimit?.toEditableString() ?? '';
    _type = account.type;
    _currency = account.currency;
    _iconName = account.iconName;
    _color = AppColors.tryParseHex(account.colorHex);
    _isActive = account.isActive;
  }

  void _applyDefaults() {
    if (_isLoaded) return;
    _isLoaded = true;
    _currency = ref.read(currencyProvider);
  }

  Future<void> _submit(Account? existing) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.hideKeyboard();

    var initialBalance =
        Money.tryParse(_balanceController.text, _currency) ??
            Money.zero(_currency);
            
    // Credit card balances are liabilities, so an opening balance is money owed
    // and must be stored as negative.
    if (_type.isCredit && !initialBalance.isZero) {
      initialBalance = -initialBalance;
    }
            
    final creditLimit = _type.isCredit
        ? Money.tryParse(_creditLimitController.text, _currency)
        : null;

    setState(() => _isSubmitting = true);
    final controller = ref.read(accountsControllerProvider.notifier);

    try {
      if (existing != null) {
        await controller.save(
          existing.copyWith(
            name: _nameController.text.trim(),
            type: _type,
            institutionName: _nullIfEmpty(_institutionController.text),
            accountNumberLast4: _nullIfEmpty(_last4Controller.text),
            creditLimit: creditLimit,
            iconName: _iconName,
            colorHex: _color == null ? null : AppColors.toHex(_color!),
            isActive: _isActive,
          ),
        );

        // The opening balance is a separate write: the database shifts the
        // current balance by the same delta, preserving every transaction
        // already posted on top of it.
        if (initialBalance != existing.initialBalance) {
          await controller.updateInitialBalance(existing.id, initialBalance);
        }
      } else {
        await controller.create(
          Account(
            id: '',
            userId: '',
            name: _nameController.text.trim(),
            type: _type,
            currency: _currency,
            initialBalance: initialBalance,
            currentBalance: initialBalance,
            institutionName: _nullIfEmpty(_institutionController.text),
            accountNumberLast4: _nullIfEmpty(_last4Controller.text),
            creditLimit: creditLimit,
            iconName: _iconName,
            colorHex: _color == null ? null : AppColors.toHex(_color!),
            isActive: _isActive,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
      }

      if (!mounted) return;
      AppFeedback.showSuccess(
        context,
        existing != null ? 'Account updated' : 'Account added',
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
    if (widget.isEditing) {
      final account = ref.watch(accountByIdProvider(widget.accountId));
      if (account == null) {
        final accounts = ref.watch(accountsControllerProvider);
        return accounts.view(
          (_) => const Scaffold(
            body: EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Account not found',
              message: 'It may have been deleted.',
            ),
          ),
          loading: const Scaffold(body: LoadingView()),
        );
      }
      _hydrate(account);
      return _buildForm(context, account);
    }

    _applyDefaults();
    return _buildForm(context, null);
  }

  Widget _buildForm(BuildContext context, Account? existing) {
    return Scaffold(
      appBar: AppBar(
        title: Text(existing != null ? 'Edit account' : 'Add account'),
        actions: [
          if (existing != null) _AccountMenu(account: existing),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.page),
            children: [
              Center(
                child: IconBadge(
                  icon: _iconName == null
                      ? _iconForType(_type)
                      : _iconForType(_type),
                  color: _color ?? context.colors.primary,
                  size: 64,
                ),
              ),
              AppSpacing.gapXl,

              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                autofocus: existing == null,
                validator: Validators.accountName,
                decoration: const InputDecoration(
                  labelText: 'Account name *',
                  hintText: 'Commercial Bank, Cash, eZ Cash…',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              AppSpacing.gapLg,

              PickerField(
                label: 'Account type',
                isRequired: true,
                value: _type.label,
                leading: Icon(_iconForType(_type), size: 20),
                onTap: () => _pickType(context),
              ),
              AppSpacing.gapLg,

              PickerField(
                label: 'Currency',
                isRequired: true,
                value: '$_currency · ${Currencies.byCode(_currency).name}',
                // Changing an account's currency after transactions exist would
                // silently reinterpret every stored amount, so it is fixed once
                // the account is created.
                enabled: existing == null,
                trailing: existing != null
                    ? Icon(
                        Icons.lock_outline_rounded,
                        size: 18,
                        color: context.palette.textTertiary,
                      )
                    : null,
                onTap: () async {
                  final picked = await CurrencyPicker.show(
                    context,
                    selectedCode: _currency,
                  );
                  if (picked != null) {
                    setState(() => _currency = picked.code);
                  }
                },
              ),
              if (existing != null)
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.xs,
                    left: AppSpacing.md,
                  ),
                  child: Text(
                    'Currency cannot be changed once an account has '
                    'transactions.',
                    style: context.text.bodySmall,
                  ),
                ),
              AppSpacing.gapLg,

              AmountField(
                controller: _balanceController,
                currency: _currency,
                label: existing == null ? 'Opening balance' : 'Opening balance',
                allowNegative: true,
                compact: true,
                helperText: existing == null
                    ? 'What is in this account right now'
                    : 'Changing this shifts the current balance by the same '
                        'amount',
                validator: (value) =>
                    Validators.signedAmount(value, currency: _currency),
              ),
              AppSpacing.gapLg,

              if (_type.isCredit) ...[
                AmountField(
                  controller: _creditLimitController,
                  currency: _currency,
                  label: 'Credit limit',
                  compact: true,
                  helperText: 'Used to show how much credit is still available',
                ),
                AppSpacing.gapLg,
              ],

              TextFormField(
                controller: _institutionController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Bank or provider',
                  hintText: 'Optional',
                  prefixIcon: Icon(Icons.account_balance_outlined),
                ),
              ),
              AppSpacing.gapLg,

              TextFormField(
                controller: _last4Controller,
                keyboardType: TextInputType.number,
                maxLength: 4,
                validator: Validators.last4,
                decoration: const InputDecoration(
                  labelText: 'Last 4 digits',
                  hintText: 'Optional',
                  prefixIcon: Icon(Icons.pin_outlined),
                  counterText: '',
                  // Stated plainly, because a user who expected to enter a full
                  // number should understand why they cannot.
                  helperText: 'Only the last 4 digits are ever stored',
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
                          color: _color ?? context.colors.primary,
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

              AppCard(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                  title: Text('Active', style: context.text.titleSmall),
                  subtitle: Text(
                    'Inactive accounts are excluded from your total balance',
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
                    : Text(existing != null ? 'Save changes' : 'Add account'),
              ),
              AppSpacing.gapXxl,
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickType(BuildContext context) async {
    final picked = await AppFeedback.showSheet<AccountType>(
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
              child: Text('Account type', style: context.text.titleLarge),
            ),
            const Divider(height: 1),
            for (final type in AccountType.values)
              ListTile(
                leading: Icon(_iconForType(type)),
                title: Text(type.label, style: context.text.titleSmall),
                trailing: type == _type
                    ? Icon(Icons.check_rounded, color: context.colors.primary)
                    : null,
                onTap: () => Navigator.of(context).pop(type),
              ),
          ],
        ),
      ),
    );

    if (picked != null) {
      setState(() {
        _type = picked;
        // A credit limit only means something on a credit card.
        if (!picked.isCredit) _creditLimitController.clear();
      });
    }
  }

  static IconData _iconForType(AccountType type) => switch (type) {
        AccountType.cash => Icons.payments_outlined,
        AccountType.bank => Icons.account_balance_outlined,
        AccountType.savings => Icons.savings_outlined,
        AccountType.debitCard => Icons.credit_card_outlined,
        AccountType.creditCard => Icons.credit_score_outlined,
        AccountType.eWallet => Icons.account_balance_wallet_outlined,
        AccountType.other => Icons.wallet_outlined,
      };
}

/// Archive and delete, kept out of the form body so they are deliberate.
class _AccountMenu extends ConsumerWidget {
  const _AccountMenu({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (value) async {
        switch (value) {
          case 'archive':
            await _archive(context, ref);
          case 'delete':
            await _delete(context, ref);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'archive',
          child: ListTile(
            leading: Icon(
              account.isArchived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
            ),
            title: Text(account.isArchived ? 'Restore' : 'Archive'),
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
    final archiving = !account.isArchived;
    final confirmed = await AppFeedback.confirm(
      context,
      title: archiving ? 'Archive account?' : 'Restore account?',
      message: archiving
          ? 'Its transactions stay in your history, and it stops appearing '
              'when you add a transaction.'
          : 'It will appear again when you add a transaction.',
      confirmLabel: archiving ? 'Archive' : 'Restore',
    );
    if (!confirmed || !context.mounted) return;

    final done = await AppFeedback.runWithProgress(
      context,
      successMessage: archiving ? 'Account archived' : 'Account restored',
      action: () async {
        await ref
            .read(accountsControllerProvider.notifier)
            .setArchived(account.id, archived: archiving);
        return true;
      },
    );

    if (done == true && context.mounted) context.pop();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final count = await ref
        .read(accountRepositoryProvider)
        .transactionCount(account.id);

    if (!context.mounted) return;

    bool force = false;
    if (count > 0) {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Account?'),
          content: Text(
            'This account has $count transaction${count == 1 ? '' : 's'}.\n\n'
            'Archiving will hide the account while keeping transaction history intact. '
            'Deleting will permanently remove this account.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'archive'),
              child: const Text('Archive instead'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: context.palette.danger,
              ),
              onPressed: () => Navigator.pop(context, 'delete'),
              child: const Text('Delete anyway'),
            ),
          ],
        ),
      );

      if (choice == 'archive' && context.mounted) {
        await _archive(context, ref);
        return;
      }
      if (choice != 'delete') return;
      force = true;
    } else {
      final confirmed = await AppFeedback.confirm(
        context,
        title: 'Delete account?',
        message: 'Are you sure you want to delete "${account.name}"?',
        confirmLabel: 'Delete',
        isDestructive: true,
      );
      if (!confirmed || !context.mounted) return;
    }

    if (!context.mounted) return;
    final done = await AppFeedback.runWithProgress(
      context,
      successMessage: 'Account deleted',
      action: () async {
        await ref
            .read(accountsControllerProvider.notifier)
            .delete(account.id, force: force);
        return true;
      },
    );

    if (done == true && context.mounted) context.pop();
  }
}
