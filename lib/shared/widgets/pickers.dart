import 'package:flutter/material.dart';

import '../../core/constants/currencies.dart';
import '../../core/constants/enums.dart';
import '../../core/extensions/context_extensions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/app_date_utils.dart';
import '../models/account.dart';
import '../models/category.dart';
import 'app_card.dart';
import 'money_text.dart';
import 'state_views.dart';

/// Selection sheets shared by every form.
///
/// Each returns the chosen value or null, so a caller reads as
/// `final account = await AccountPicker.show(context, accounts: ...)`.

class AccountPicker {
  const AccountPicker._();

  static Future<Account?> show(
    BuildContext context, {
    required List<Account> accounts,
    String? selectedId,
    String title = 'Select account',
    String? excludeId,
    bool showBalances = true,
  }) {
    final available = accounts
        .where((a) => a.id != excludeId && a.isActive && !a.isArchived)
        .toList();

    return showModalBottomSheet<Account>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => _PickerSheet(
        title: title,
        child: available.isEmpty
            ? const EmptyState(
                icon: Icons.account_balance_wallet_outlined,
                title: 'No accounts available',
                message: 'Add an account first so transactions have somewhere '
                    'to live.',
                compact: true,
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: available.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final account = available[index];
                  return ListTile(
                    leading: IconBadge(
                      icon: account.icon,
                      color: account.color,
                    ),
                    title: Text(account.name, style: context.text.titleSmall),
                    subtitle: Text(
                      account.subtitle,
                      style: context.text.bodySmall,
                    ),
                    trailing: showBalances
                        ? MoneyText.balance(
                            account.currentBalance,
                            size: MoneySize.row,
                          )
                        : null,
                    selected: account.id == selectedId,
                    onTap: () => Navigator.of(context).pop(account),
                  );
                },
              ),
      ),
    );
  }
}

class CategoryPicker {
  const CategoryPicker._();

  /// A grid rather than a list: category choice is recognition, and icons are
  /// faster to recognise than names in a column.
  static Future<Category?> show(
    BuildContext context, {
    required List<Category> categories,
    String? selectedId,
    String title = 'Select category',
    bool allowNone = false,
  }) {
    final available = categories.where((c) => !c.isArchived).toList();

    return showModalBottomSheet<Category?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => _PickerSheet(
        title: title,
        trailing: allowNone
            ? TextButton(
                onPressed: () => Navigator.of(context).pop(_noCategory),
                child: const Text('Clear'),
              )
            : null,
        child: available.isEmpty
            ? const EmptyState(
                icon: Icons.category_outlined,
                title: 'No categories',
                message: 'Create a category to organise your spending.',
                compact: true,
              )
            : GridView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(AppSpacing.lg),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 110,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  childAspectRatio: 0.92,
                ),
                itemCount: available.length,
                itemBuilder: (context, index) {
                  final category = available[index];
                  final isSelected = category.id == selectedId;
                  return InkWell(
                    onTap: () => Navigator.of(context).pop(category),
                    borderRadius: AppRadius.mdAll,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: AppRadius.mdAll,
                        border: Border.all(
                          color: isSelected
                              ? category.color
                              : context.colors.outline,
                          width: isSelected ? 1.8 : 1,
                        ),
                        color: isSelected
                            ? category.color.withValues(alpha: 0.08)
                            : null,
                      ),
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconBadge(
                            icon: category.icon,
                            color: category.color,
                            size: 38,
                          ),
                          AppSpacing.gapSm,
                          Text(
                            category.name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelMedium?.copyWith(
                              color: context.colors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  /// Sentinel returned when the user clears the selection, so the caller can
  /// tell "cleared" apart from "dismissed without choosing".
  static final Category noCategory = _noCategory;

  static final Category _noCategory = Category(
    id: '__none__',
    userId: '',
    name: 'None',
    kind: CategoryKind.expense,
    createdAt: DateTime(2000),
    updatedAt: DateTime(2000),
  );

  static bool isNone(Category? category) => category?.id == '__none__';
}

class PaymentMethodPicker {
  const PaymentMethodPicker._();

  static Future<PaymentMethod?> show(
    BuildContext context, {
    PaymentMethod? selected,
  }) {
    return showModalBottomSheet<PaymentMethod>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => _PickerSheet(
        title: 'Payment method',
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final method in PaymentMethod.values)
              ListTile(
                leading: Icon(_iconFor(method)),
                title: Text(method.label, style: context.text.titleSmall),
                selected: method == selected,
                trailing: method == selected
                    ? Icon(Icons.check_rounded, color: context.colors.primary)
                    : null,
                onTap: () => Navigator.of(context).pop(method),
              ),
          ],
        ),
      ),
    );
  }

  static IconData iconFor(PaymentMethod method) => _iconFor(method);

  static IconData _iconFor(PaymentMethod method) => switch (method) {
        PaymentMethod.cash => Icons.payments_outlined,
        PaymentMethod.debitCard => Icons.credit_card_outlined,
        PaymentMethod.creditCard => Icons.credit_score_outlined,
        PaymentMethod.bankTransfer => Icons.account_balance_outlined,
        PaymentMethod.onlineBanking => Icons.language_rounded,
        PaymentMethod.eWallet => Icons.account_balance_wallet_outlined,
        PaymentMethod.qrPayment => Icons.qr_code_scanner_rounded,
        PaymentMethod.other => Icons.more_horiz_rounded,
      };
}

class CurrencyPicker {
  const CurrencyPicker._();

  static Future<CurrencyInfo?> show(
    BuildContext context, {
    String? selectedCode,
  }) {
    return showModalBottomSheet<CurrencyInfo>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => _PickerSheet(
        title: 'Currency',
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final currency in Currencies.all)
              ListTile(
                leading: SizedBox(
                  width: 36,
                  child: Text(
                    currency.symbol,
                    textAlign: TextAlign.center,
                    style: context.text.titleMedium,
                  ),
                ),
                title: Text(currency.code, style: context.text.titleSmall),
                subtitle: Text(currency.name, style: context.text.bodySmall),
                selected: currency.code == selectedCode,
                trailing: currency.code == selectedCode
                    ? Icon(Icons.check_rounded, color: context.colors.primary)
                    : null,
                onTap: () => Navigator.of(context).pop(currency),
              ),
          ],
        ),
      ),
    );
  }
}

class IconPicker {
  const IconPicker._();

  static Future<String?> show(
    BuildContext context, {
    String? selectedName,
    List<String>? names,
  }) {
    final options = names ?? CategoryIcons.pickerNames;

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => _PickerSheet(
        title: 'Choose an icon',
        child: GridView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.all(AppSpacing.lg),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 64,
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
          ),
          itemCount: options.length,
          itemBuilder: (context, index) {
            final name = options[index];
            final isSelected = name == selectedName;
            return InkWell(
              onTap: () => Navigator.of(context).pop(name),
              borderRadius: AppRadius.mdAll,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(
                    color: isSelected
                        ? context.colors.primary
                        : context.colors.outline,
                    width: isSelected ? 1.8 : 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  CategoryIcons.resolve(name),
                  size: 22,
                  color: isSelected
                      ? context.colors.primary
                      : context.palette.textSecondary,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class ColorPicker {
  const ColorPicker._();

  static Future<Color?> show(
    BuildContext context, {
    Color? selected,
  }) {
    return showModalBottomSheet<Color>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => _PickerSheet(
        title: 'Choose a colour',
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              for (final color in AppColors.categoryPalette)
                InkWell(
                  onTap: () => Navigator.of(context).pop(color),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected?.toARGB32() == color.toARGB32()
                            ? context.colors.onSurface
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: selected?.toARGB32() == color.toARGB32()
                        ? const Icon(
                            Icons.check_rounded,
                            size: 20,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Date and time selection, with the app's constraints applied.
class DateTimePickers {
  const DateTimePickers._();

  /// A transaction date. Bounded to a sensible window because a date years in
  /// the future is almost always a typo or an OCR misread of the year.
  static Future<DateTime?> pickTransactionDate(
    BuildContext context, {
    required DateTime initial,
  }) {
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Transaction date',
    );
  }

  static Future<TimeOfDay?> pickTime(
    BuildContext context, {
    required DateTime initial,
  }) {
    return showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Transaction time',
    );
  }

  /// A future date, for bill due dates and savings targets.
  static Future<DateTime?> pickFutureDate(
    BuildContext context, {
    DateTime? initial,
    String helpText = 'Select date',
  }) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 15),
      helpText: helpText,
    );
  }

  static Future<DateRange?> pickRange(
    BuildContext context, {
    DateRange? initial,
  }) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: initial == null
          ? null
          : DateTimeRange(start: initial.start, end: initial.end),
      helpText: 'Select period',
    );
    if (picked == null) return null;
    return DateRange(
      AppDateUtils.startOfDay(picked.start),
      AppDateUtils.endOfDay(picked.end),
    );
  }
}

/// The chrome shared by every picker sheet.
class _PickerSheet extends StatelessWidget {
  const _PickerSheet({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(child: Text(title, style: context.text.titleLarge)),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(child: child),
        ],
      ),
    );
  }
}
