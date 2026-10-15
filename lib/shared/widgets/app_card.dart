import 'dart:ui';
import 'package:flutter/material.dart';

import '../../core/extensions/context_extensions.dart';
import '../../core/theme/app_spacing.dart';

/// The glass container every block of content sits in.
///
/// Uses frosted glass with backdrop blur, translucent fill, and soft glowing
/// hairline borders for a modern, sleek UI.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.cardInsets,
    this.onTap,
    this.color,
    this.borderColor,
    this.borderRadius = AppRadius.xlAll,
    this.showShadow = true,
    this.isGlass = true,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final BorderRadius borderRadius;
  final bool showShadow;
  final bool isGlass;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    final glassColor = color ??
        (isDark
            ? const Color(0x5512243E)
            : const Color(0xD8FFFFFF));

    final glassBorder = borderColor ??
        (isDark
            ? const Color(0xFF4A7FA7).withValues(alpha: 0.25)
            : const Color(0xFFB3CFE5).withValues(alpha: 0.65));

    final glassShadow = showShadow
        ? [
            BoxShadow(
              color: isDark
                  ? const Color(0xFF0A1931).withValues(alpha: 0.5)
                  : const Color(0xFF1A3D63).withValues(alpha: 0.08),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 6),
            ),
          ]
        : null;

    final cardChild = onTap == null
        ? Padding(padding: padding, child: child)
        : Material(
            color: Colors.transparent,
            borderRadius: borderRadius,
            child: InkWell(
              onTap: onTap,
              borderRadius: borderRadius,
              child: Padding(padding: padding, child: child),
            ),
          );

    final content = isGlass
        ? Container(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              boxShadow: glassShadow,
            ),
            child: ClipRRect(
              borderRadius: borderRadius,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  decoration: BoxDecoration(
                    color: glassColor,
                    borderRadius: borderRadius,
                    border: Border.all(
                      color: glassBorder,
                      width: 1.2,
                    ),
                  ),
                  child: cardChild,
                ),
              ),
            ),
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              color: color ?? context.colors.surface,
              borderRadius: borderRadius,
              border: Border.all(color: borderColor ?? context.colors.outline),
              boxShadow: showShadow ? AppElevation.card(isDark) : null,
            ),
            child: cardChild,
          );

    return margin == null
        ? content
        : Padding(padding: margin!, child: content);
  }
}

/// A card with a title row and an optional trailing action.
class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
    this.icon,
    this.padding = AppSpacing.cardInsets,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;
  final IconData? icon;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: padding,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: context.palette.textSecondary),
                AppSpacing.hGapSm,
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.titleMedium),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xxs),
                        child: Text(
                          subtitle!,
                          style: context.text.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
              if (action != null) action!,
            ],
          ),
          AppSpacing.gapLg,
          child,
        ],
      ),
    );
  }
}

/// A screen-level section heading, used outside cards.
class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.page,
      AppSpacing.xxl,
      AppSpacing.page,
      AppSpacing.md,
    ),
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: Text(title, style: context.text.titleLarge)),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// A key/value row, used in detail screens.
class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.label,
    this.value,
    this.valueWidget,
    this.icon,
    this.onTap,
    this.isMultiline = false,
  });

  final String label;
  final String? value;
  final Widget? valueWidget;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool isMultiline;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment:
            isMultiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: context.palette.textTertiary),
            AppSpacing.hGapMd,
          ],
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: context.text.bodyMedium
                  ?.copyWith(color: context.palette.textSecondary),
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child: valueWidget ??
                  Text(
                    value ?? '—',
                    textAlign: TextAlign.end,
                    style: context.text.titleSmall,
                  ),
            ),
          ),
          if (onTap != null) ...[
            AppSpacing.hGapSm,
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: context.palette.textTertiary,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.smAll,
      child: content,
    );
  }
}

/// A circular icon badge, tinted by a semantic or category colour.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
    this.iconSize,
    this.isSquare = false,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double? iconSize;
  final bool isSquare;

  @override
  Widget build(BuildContext context) {
    // A low-opacity fill of the same hue keeps the badge readable in both
    // themes without needing a second colour token per category.
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.22 : 0.12),
        shape: isSquare ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: isSquare ? AppRadius.mdAll : null,
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: iconSize ?? size * 0.5,
        color: context.isDark ? _lighten(color) : color,
      ),
    );
  }

  /// Category colours are chosen for light surfaces; on a dark surface the same
  /// hue needs lifting to stay legible.
  static Color _lighten(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + 0.22).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation * 0.9).clamp(0.0, 1.0))
        .toColor();
  }
}

/// A small pill label, for statuses and sources.
class AppChipLabel extends StatelessWidget {
  const AppChipLabel({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.dense = false,
  });

  final String label;
  final Color? color;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.palette.textSecondary;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.sm : AppSpacing.md,
        vertical: dense ? 2 : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: context.isDark ? 0.2 : 0.1),
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 13, color: tint),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: (dense ? context.text.labelSmall : context.text.labelMedium)
                ?.copyWith(color: tint, letterSpacing: 0),
          ),
        ],
      ),
    );
  }
}
