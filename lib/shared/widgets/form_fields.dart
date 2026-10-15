import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/currencies.dart';
import '../../core/extensions/context_extensions.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money.dart';

/// The amount input.
///
/// Accepts only digits and one decimal separator, capped at the currency's
/// decimal places, so a value that cannot be stored can never be typed. The
/// field is large and leading because on an expense form the amount is the one
/// thing the user came to enter.
class AmountField extends StatefulWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.currency,
    this.label = 'Amount',
    this.autofocus = false,
    this.validator,
    this.onChanged,
    this.enabled = true,
    this.allowNegative = false,
    this.helperText,
    this.compact = false,
    this.focusNode,
  });

  final TextEditingController controller;
  final String currency;
  final String label;
  final bool autofocus;
  final String? Function(String?)? validator;
  final ValueChanged<Money?>? onChanged;
  final bool enabled;

  /// Opening balances may legitimately be negative; transaction amounts may not.
  final bool allowNegative;
  final String? helperText;
  final bool compact;
  final FocusNode? focusNode;

  @override
  State<AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<AmountField> {
  @override
  Widget build(BuildContext context) {
    final info = Currencies.byCode(widget.currency);

    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      keyboardType: TextInputType.numberWithOptions(
        decimal: info.decimals > 0,
        signed: widget.allowNegative,
      ),
      textAlign: TextAlign.end,
      style: widget.compact
          ? context.text.titleMedium
          : context.text.headlineMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
      inputFormatters: [
        _AmountInputFormatter(
          decimals: info.decimals,
          allowNegative: widget.allowNegative,
        ),
      ],
      decoration: InputDecoration(
        labelText: widget.label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        helperText: widget.helperText,
        // The symbol is part of the field rather than typed, so the user is
        // never unsure which currency they are entering.
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.sm),
          child: Align(
            widthFactor: 1.0,
            heightFactor: 1.0,
            alignment: Alignment.centerLeft,
            child: Text(
              info.symbol,
              style: (widget.compact
                      ? context.text.titleMedium
                      : context.text.titleLarge)
                  ?.copyWith(color: context.palette.textSecondary),
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        hintText: info.decimals == 0 ? '0' : '0.${'0' * info.decimals}',
      ),
      validator: widget.validator,
      onChanged: (value) {
        widget.onChanged?.call(Money.tryParse(value, widget.currency));
      },
    );
  }
}

/// Keeps the text a valid money string as it is typed.
class _AmountInputFormatter extends TextInputFormatter {
  _AmountInputFormatter({required this.decimals, required this.allowNegative});

  final int decimals;
  final bool allowNegative;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final pattern = decimals > 0
        ? RegExp(allowNegative ? r'^-?\d*\.?\d{0,' '$decimals' r'}$'
            : r'^\d*\.?\d{0,' '$decimals' r'}$')
        : RegExp(allowNegative ? r'^-?\d*$' : r'^\d*$');

    if (!pattern.hasMatch(text)) return oldValue;

    // A single leading dot is a common slip; make it "0." rather than rejecting
    // the keystroke, which feels like the keyboard is broken.
    if (text == '.') {
      return const TextEditingValue(
        text: '0.',
        selection: TextSelection.collapsed(offset: 2),
      );
    }

    // Guard against absurd values that would overflow numeric(16,2).
    final digitsBeforeDot = text.split('.').first.replaceAll('-', '').length;
    if (digitsBeforeDot > 13) return oldValue;

    return newValue;
  }
}

/// Quick-add buttons that append zeros, for entering round amounts fast.
class AmountQuickActions extends StatelessWidget {
  const AmountQuickActions({
    super.key,
    required this.controller,
    required this.currency,
    this.onChanged,
  });

  final TextEditingController controller;
  final String currency;
  final ValueChanged<Money?>? onChanged;

  static const List<int> _increments = [100, 500, 1000, 5000];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      children: [
        for (final increment in _increments)
          ActionChip(
            label: Text('+${_formatIncrement(increment)}'),
            onPressed: () => _add(increment),
            visualDensity: VisualDensity.compact,
          ),
        ActionChip(
          label: const Text('Clear'),
          onPressed: () {
            controller.clear();
            onChanged?.call(null);
          },
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  String _formatIncrement(int value) =>
      value >= 1000 ? '${value ~/ 1000}k' : '$value';

  void _add(int increment) {
    final current = Money.tryParse(controller.text, currency) ??
        Money.zero(currency);
    final next = current + Money.fromMajor(increment, currency);
    controller.text = next.toEditableString();
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    onChanged?.call(next);
  }
}

/// A read-only field that opens a picker when tapped.
///
/// Used for accounts, categories, dates and payment methods so every selection
/// control on a form looks and behaves the same.
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.onTap,
    this.value,
    this.placeholder = 'Select',
    this.leading,
    this.trailing,
    this.errorText,
    this.enabled = true,
    this.isRequired = false,
  });

  final String label;
  final String? value;
  final String placeholder;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback onTap;
  final String? errorText;
  final bool enabled;
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.isNotEmpty;

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: AppRadius.mdAll,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: isRequired ? '$label *' : label,
          hintText: hasValue ? null : placeholder,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          errorText: errorText,
          enabled: enabled,
          suffixIcon: trailing ??
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: context.palette.textTertiary,
              ),
        ),
        isEmpty: !hasValue,
        child: hasValue
            ? Row(
                children: [
                  if (leading != null) ...[leading!, AppSpacing.hGapMd],
                  Expanded(
                    child: Text(
                      value!,
                      style: context.text.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : (leading != null
                ? Row(
                    children: [
                      leading!,
                      AppSpacing.hGapMd,
                      Expanded(
                        child: Text(
                          placeholder,
                          style: context.text.bodyLarge?.copyWith(
                            color: context.palette.textTertiary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                : null),
      ),
    );
  }
}

/// A row of segmented options, used for the expense/income/transfer switch.
class SegmentedTypeSelector<T> extends StatelessWidget {
  const SegmentedTypeSelector({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.labelFor,
    this.colorFor,
    this.iconFor,
  });

  final List<T> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final String Function(T)? labelFor;
  final Color Function(T)? colorFor;
  final IconData Function(T)? iconFor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: context.palette.surfaceAlt,
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: _SegmentButton(
                label: labelFor?.call(option) ?? option.toString(),
                icon: iconFor?.call(option),
                // The selected segment takes the semantic colour of the thing it
                // selects, so the form reads as "this is an expense" at a glance.
                color: colorFor?.call(option) ?? context.colors.primary,
                isSelected: option == selected,
                onTap: () => onChanged(option),
              ),
            ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: isSelected ? context.colors.surface : Colors.transparent,
        borderRadius: AppRadius.smAll,
        boxShadow: isSelected ? AppElevation.card(context.isDark) : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.smAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.smAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 16,
                    color: isSelected ? color : context.palette.textTertiary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall?.copyWith(
                      color: isSelected ? color : context.palette.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
