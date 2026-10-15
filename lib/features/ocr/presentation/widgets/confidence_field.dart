import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/models/transaction_candidate.dart';
import '../../../../shared/widgets/app_card.dart';

/// How confident the parser was about one field.
enum ConfidenceLevel { high, medium, low, missing }

ConfidenceLevel confidenceLevelFor(double? score, {required bool hasValue}) {
  if (!hasValue) return ConfidenceLevel.missing;
  // A field with no score at all counts as unverified: silence is not
  // confidence, and treating it as such is how wrong figures get saved.
  if (score == null) return ConfidenceLevel.low;
  if (score >= 0.92) return ConfidenceLevel.high;
  if (score >= AppConstants.lowConfidenceThreshold) return ConfidenceLevel.medium;
  return ConfidenceLevel.low;
}

/// A badge showing a field's confidence.
///
/// The percentage is shown alongside the verdict so a user can see the
/// difference between "probably right" and "barely legible", rather than being
/// given a binary they cannot reason about.
class ConfidenceBadge extends StatelessWidget {
  const ConfidenceBadge({
    super.key,
    required this.level,
    this.score,
    this.dense = true,
  });

  final ConfidenceLevel level;
  final double? score;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (level) {
      ConfidenceLevel.high => (
          'High confidence',
          Icons.check_circle_outline_rounded,
          context.palette.income,
        ),
      ConfidenceLevel.medium => (
          'Please check',
          Icons.help_outline_rounded,
          context.palette.warning,
        ),
      ConfidenceLevel.low => (
          'Please verify',
          Icons.warning_amber_rounded,
          context.palette.warning,
        ),
      ConfidenceLevel.missing => (
          'Not detected',
          Icons.error_outline_rounded,
          context.palette.danger,
        ),
    };

    final suffix = score == null || level == ConfidenceLevel.missing
        ? ''
        : ' · ${(score! * 100).round()}%';

    return AppChipLabel(
      label: '$label$suffix',
      icon: icon,
      color: color,
      dense: dense,
    );
  }
}

/// Wraps a form field with its confidence badge and the source line it came
/// from, so the user can check the extraction against the document.
class ReviewField extends StatelessWidget {
  const ReviewField({
    super.key,
    required this.label,
    required this.child,
    required this.level,
    this.score,
    this.rawText,
    this.isRequired = false,
  });

  final String label;
  final Widget child;
  final ConfidenceLevel level;
  final double? score;

  /// The line of OCR text this value was read from.
  final String? rawText;
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    final needsAttention = level == ConfidenceLevel.low ||
        level == ConfidenceLevel.missing ||
        level == ConfidenceLevel.medium;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: AppRadius.mdAll,
        // A tinted surround rather than a red border on the input itself: the
        // value is not invalid, it is unverified, and those should not look the
        // same.
        color: needsAttention
            ? (level == ConfidenceLevel.missing
                    ? context.palette.danger
                    : context.palette.warning)
                .withValues(alpha: context.isDark ? 0.09 : 0.05)
            : Colors.transparent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isRequired ? '$label *' : label,
                  style: context.text.labelMedium,
                ),
              ),
              ConfidenceBadge(level: level, score: score),
            ],
          ),
          AppSpacing.gapSm,
          child,
          if (rawText != null && rawText!.trim().isNotEmpty) ...[
            AppSpacing.gapSm,
            _RawTextHint(text: rawText!),
          ],
        ],
      ),
    );
  }
}

class _RawTextHint extends StatelessWidget {
  const _RawTextHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.subject_rounded,
          size: 13,
          color: context.palette.textTertiary,
        ),
        AppSpacing.hGapSm,
        Expanded(
          child: Text(
            'Read from: "${text.trim()}"',
            style: context.text.bodySmall
                ?.copyWith(color: context.palette.textTertiary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// The warnings banner above the review form.
class CandidateWarnings extends StatelessWidget {
  const CandidateWarnings({super.key, required this.warnings});

  final List<CandidateWarning> warnings;

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty) {
      return AppCard(
        borderColor: context.palette.income.withValues(alpha: 0.4),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 20,
              color: context.palette.income,
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: Text(
                'Everything looks readable. Check the details and confirm.',
                style: context.text.bodyMedium
                    ?.copyWith(color: context.colors.onSurface),
              ),
            ),
          ],
        ),
      );
    }

    final blocking = warnings.where((w) => w.blocking).toList();
    final advisory = warnings.where((w) => !w.blocking).toList();
    final color = blocking.isNotEmpty
        ? context.palette.danger
        : context.palette.warning;

    return AppCard(
      borderColor: color.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                blocking.isNotEmpty
                    ? Icons.error_outline_rounded
                    : Icons.warning_amber_rounded,
                size: 20,
                color: color,
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: Text(
                  blocking.isNotEmpty
                      ? 'A few details are needed before saving'
                      : 'Worth double-checking',
                  style: context.text.titleSmall?.copyWith(color: color),
                ),
              ),
            ],
          ),
          AppSpacing.gapMd,
          // Blocking items first: those are the ones the user must act on.
          for (final warning in [...blocking, ...advisory])
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    warning.blocking
                        ? Icons.priority_high_rounded
                        : Icons.info_outline_rounded,
                    size: 15,
                    color: warning.blocking
                        ? context.palette.danger
                        : context.palette.textTertiary,
                  ),
                  AppSpacing.hGapSm,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          warning.title,
                          style: context.text.titleSmall?.copyWith(
                            fontSize: 13,
                            color: context.colors.onSurface,
                          ),
                        ),
                        Text(
                          warning.detail,
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
