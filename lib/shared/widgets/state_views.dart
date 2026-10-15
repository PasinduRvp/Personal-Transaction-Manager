import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/extensions/context_extensions.dart';
import '../../core/theme/app_spacing.dart';

/// The four states every screen needs: loading, empty, error, and content.
///
/// Centralised so no screen invents its own, and so an error never reaches the
/// user as a raw exception — everything goes through [ErrorMapper] first.

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message, this.compact = false});

  final String? message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final indicator = SizedBox(
      width: compact ? 20 : 32,
      height: compact ? 20 : 32,
      child: CircularProgressIndicator(strokeWidth: compact ? 2 : 3),
    );

    if (compact) return Center(child: indicator);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          indicator,
          if (message != null) ...[
            AppSpacing.gapLg,
            Text(message!, style: context.text.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// The empty state: explains what the screen is for and offers the one action
/// that fills it, rather than leaving the user looking at blank space.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: compact ? AppSpacing.xxl : AppSpacing.huge,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: compact ? 56 : 72,
              height: compact ? 56 : 72,
              decoration: BoxDecoration(
                color: context.palette.surfaceAlt,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: compact ? 26 : 34,
                color: context.palette.textTertiary,
              ),
            ),
            AppSpacing.gapXl,
            Text(
              title,
              textAlign: TextAlign.center,
              style: compact ? context.text.titleMedium : context.text.titleLarge,
            ),
            AppSpacing.gapSm,
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.text.bodyMedium,
            ),
            if (actionLabel != null && onAction != null) ...[
              AppSpacing.gapXxl,
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(actionLabel!),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxl,
                  ),
                ),
              ),
            ],
            if (secondaryActionLabel != null && onSecondaryAction != null) ...[
              AppSpacing.gapSm,
              TextButton(
                onPressed: onSecondaryAction,
                child: Text(secondaryActionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The error state.
///
/// Takes the raw error and maps it, so a screen can pass whatever it caught and
/// still show a sentence a person can act on. Technical detail is logged, never
/// rendered.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    required this.error,
    this.onRetry,
    this.compact = false,
    this.retryLabel = 'Try again',
  });

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final mapped = ErrorMapper.map(error);
    final suggestions = mapped is OcrException ? mapped.suggestions : const [];

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: compact ? 48 : 64,
              height: compact ? 48 : 64,
              decoration: BoxDecoration(
                color: context.palette.danger
                    .withValues(alpha: context.isDark ? 0.2 : 0.1),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                _iconFor(mapped),
                size: compact ? 24 : 30,
                color: context.palette.danger,
              ),
            ),
            AppSpacing.gapXl,
            Text(
              _titleFor(mapped),
              textAlign: TextAlign.center,
              style: context.text.titleMedium,
            ),
            AppSpacing.gapSm,
            Text(
              mapped.message,
              textAlign: TextAlign.center,
              style: context.text.bodyMedium,
            ),
            if (suggestions.isNotEmpty) ...[
              AppSpacing.gapLg,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final suggestion in suggestions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('•  ', style: context.text.bodyMedium),
                          Expanded(
                            child: Text(
                              suggestion,
                              style: context.text.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
            if (onRetry != null) ...[
              AppSpacing.gapXxl,
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(retryLabel),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxl,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(AppException error) => switch (error) {
        NetworkException() => Icons.wifi_off_rounded,
        AuthenticationException() => Icons.lock_outline_rounded,
        PermissionException() => Icons.block_rounded,
        NotFoundException() => Icons.search_off_rounded,
        OcrException() => Icons.document_scanner_outlined,
        FileException() => Icons.insert_drive_file_outlined,
        ValidationException() => Icons.error_outline_rounded,
        _ => Icons.error_outline_rounded,
      };

  static String _titleFor(AppException error) => switch (error) {
        NetworkException() => 'No connection',
        AuthenticationException() => 'Please sign in again',
        PermissionException() => 'Not available',
        NotFoundException() => 'Not found',
        OcrException() => "We couldn't read that document",
        ValidationException() => 'Check your details',
        _ => 'Something went wrong',
      };
}

/// A grey block that pulses while data loads.
///
/// Used in place of a spinner where the final layout is known, because a
/// skeleton that matches the content avoids the jump a spinner causes when the
/// real thing arrives.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = AppRadius.smAll,
  });

  final double? width;
  final double height;
  final BorderRadius borderRadius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(
              context.palette.shimmerBase,
              context.palette.shimmerHighlight,
              _controller.value,
            ),
            borderRadius: widget.borderRadius,
          ),
        );
      },
    );
  }
}

/// A skeleton shaped like a transaction row.
class TransactionSkeleton extends StatelessWidget {
  const TransactionSkeleton({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.page,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                const Skeleton(
                  width: 40,
                  height: 40,
                  borderRadius: AppRadius.pillAll,
                ),
                AppSpacing.hGapMd,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton(width: 120 + (i % 3) * 30, height: 14),
                      AppSpacing.gapSm,
                      const Skeleton(width: 80, height: 11),
                    ],
                  ),
                ),
                const Skeleton(width: 70, height: 14),
              ],
            ),
          ),
      ],
    );
  }
}

/// A skeleton shaped like a summary card.
class CardSkeleton extends StatelessWidget {
  const CardSkeleton({super.key, this.height = 120});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Skeleton(height: height, borderRadius: AppRadius.lgAll);
  }
}

/// Renders an [AsyncValue] through the standard states.
///
/// One place decides what loading and error look like, so a new screen gets
/// consistent behaviour by construction rather than by remembering to.
///
/// Note the order of the checks: data that is present but stale (a refresh in
/// flight, or an error after a successful load) keeps rendering rather than
/// flashing a spinner or an error page over content the user was reading.
extension AsyncValueViews<T> on AsyncValue<T> {
  Widget view(
    Widget Function(T data) builder, {
    Widget? loading,
    VoidCallback? onRetry,
    bool errorCompact = false,
  }) {
    final data = valueOrNull;
    if (data != null) return builder(data);

    final failure = error;
    if (failure != null) {
      return ErrorStateView(
        error: failure,
        onRetry: onRetry,
        compact: errorCompact,
      );
    }

    return loading ?? const LoadingView();
  }
}
