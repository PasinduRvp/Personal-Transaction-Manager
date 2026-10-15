import 'dart:ui';
import 'package:flutter/material.dart';

import '../../core/constants/enums.dart';
import '../../core/extensions/context_extensions.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/money.dart';

/// How prominent a monetary figure is.
enum MoneySize { hero, large, row, small }

/// Renders an amount with the right colour, sign and weight.
///
/// Colour carries meaning here: income green, expense red, transfers blue,
/// neutral for balances. Centralising it means a figure cannot be shown in the
/// wrong colour on one screen, which in a finance app reads as a wrong number.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.amount, {
    super.key,
    this.size = MoneySize.row,
    this.type,
    this.showSign = false,
    this.color,
    this.compact = false,
    this.obscured = false,
    this.textAlign,
    this.decimals = true,
  });

  /// A balance or total, coloured neutrally unless it is negative.
  const MoneyText.balance(
    this.amount, {
    super.key,
    this.size = MoneySize.large,
    this.compact = false,
    this.obscured = false,
    this.textAlign,
    this.decimals = true,
  })  : type = null,
        showSign = false,
        color = null;

  /// A transaction amount, coloured and signed by its type.
  const MoneyText.transaction(
    this.amount, {
    super.key,
    required TransactionType transactionType,
    this.size = MoneySize.row,
    this.obscured = false,
    this.textAlign,
  })  : type = transactionType,
        showSign = true,
        color = null,
        compact = false,
        decimals = true;

  final Money amount;
  final MoneySize size;

  /// When set, drives the colour and the sign.
  final TransactionType? type;
  final bool showSign;
  final Color? color;
  final bool compact;

  /// Replaces the figure with dots, for the privacy toggle.
  final bool obscured;
  final TextAlign? textAlign;
  final bool decimals;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? _colorFor(context);
    final style = switch (size) {
      MoneySize.hero => AppTypography.amountHero(resolved),
      MoneySize.large => AppTypography.amountLarge(resolved),
      MoneySize.row => AppTypography.amountRow(resolved),
      MoneySize.small => AppTypography.numericSmall(resolved),
    };

    if (obscured) {
      return Text(
        '****',
        style: style.copyWith(letterSpacing: 2),
        textAlign: textAlign,
      );
    }

    return Text(
      _format(),
      style: style,
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _format() {
    if (compact) return amount.formatCompact();

    final body = amount.format(showDecimals: decimals);
    if (!showSign) return body;

    // A transfer is neither a gain nor a loss overall, so it is shown unsigned
    // even though its two legs move money in opposite directions.
    if (type == TransactionType.transfer) return body;

    if (type == TransactionType.income || amount.isPositive && type == null) {
      return amount.isNegative ? body : '+$body';
    }
    if (type == TransactionType.expense) {
      return amount.isNegative ? body : '-$body';
    }
    return body;
  }

  Color _colorFor(BuildContext context) {
    final palette = context.palette;
    if (type != null) {
      return switch (type!) {
        TransactionType.income => palette.income,
        TransactionType.expense => palette.expense,
        TransactionType.transfer => palette.transfer,
      };
    }
    // A neutral figure only turns red when it is actually negative — a
    // zero balance is not a problem and should not be coloured like one.
    if (amount.isNegative) return palette.expense;
    return context.colors.onSurface;
  }
}

/// A labelled figure, used on summary tiles.
class MoneyTile extends StatelessWidget {
  const MoneyTile({
    super.key,
    required this.label,
    required this.amount,
    this.type,
    this.icon,
    this.changePercent,
    this.obscured = false,
    this.onTap,
    this.subtitle,
  });

  final String label;
  final Money amount;
  final TransactionType? type;
  final IconData? icon;

  /// Period-over-period change. Null when there is no comparable period.
  final double? changePercent;
  final bool obscured;
  final VoidCallback? onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: context.palette.textTertiary),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  style: context.text.labelMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          MoneyText(
            amount,
            size: MoneySize.large,
            type: type,
            obscured: obscured,
          ),
          if (changePercent != null) ...[
            const SizedBox(height: 4),
            _ChangeIndicator(
              percent: changePercent!,
              // For expenses, spending less is the good direction.
              invertColour: type == TransactionType.expense,
            ),
          ] else if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: context.text.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _ChangeIndicator extends StatelessWidget {
  const _ChangeIndicator({required this.percent, this.invertColour = false});

  final double percent;
  final bool invertColour;

  @override
  Widget build(BuildContext context) {
    final isUp = percent >= 0;
    final isGood = invertColour ? !isUp : isUp;
    final color = percent.abs() < 0.5
        ? context.palette.textTertiary
        : (isGood ? context.palette.income : context.palette.expense);

    return Row(
      children: [
        Icon(
          percent.abs() < 0.5
              ? Icons.remove_rounded
              : (isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
          size: 12,
          color: color,
        ),
        const SizedBox(width: 2),
        Text(
          '${percent.abs().toStringAsFixed(percent.abs() >= 10 ? 0 : 1)}%',
          style: AppTypography.numericSmall(color),
        ),
        const SizedBox(width: 4),
        Text(
          'vs last month',
          style: context.text.labelSmall?.copyWith(
            letterSpacing: 0,
            color: context.palette.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// A labelled progress bar for budgets and savings goals.
class ProgressMeter extends StatelessWidget {
  const ProgressMeter({
    super.key,
    required this.fraction,
    required this.color,
    this.height = 8,
    this.backgroundColor,
    this.showOverflow = false,
  });

  /// 0–1, already clamped by the caller.
  final double fraction;
  final Color color;
  final double height;
  final Color? backgroundColor;

  /// Draws a hatched cap when the value exceeded 100%, so an overspend is
  /// visible rather than looking like an exactly-full bar.
  final bool showOverflow;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Stack(
        children: [
          Container(
            height: height,
            color: backgroundColor ?? context.palette.surfaceAlt,
          ),
          FractionallySizedBox(
            widthFactor: fraction.clamp(0.0, 1.0),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(height),
              ),
            ),
          ),
          if (showOverflow)
            Positioned(
              right: 0,
              child: Container(
                height: height,
                width: height * 1.5,
                color: color.withValues(alpha: 0.55),
              ),
            ),
        ],
      ),
    );
  }
}
