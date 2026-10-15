import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/extensions/context_extensions.dart';
import '../../core/theme/app_spacing.dart';

/// Snackbars, dialogs and sheets, in one place.
///
/// Every error path in the UI goes through [showError], which maps the error
/// first — so a stack trace, a storage path or a PostgREST code can never reach
/// a user, whatever a screen forgets to handle.
class AppFeedback {
  const AppFeedback._();

  static void showSuccess(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _show(
      context,
      message: message,
      icon: Icons.check_circle_outline_rounded,
      iconColor: context.palette.success,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void showInfo(BuildContext context, String message) {
    _show(
      context,
      message: message,
      icon: Icons.info_outline_rounded,
      iconColor: context.palette.info,
    );
  }

  /// Shows a failure. Accepts the raw error so callers do not have to remember
  /// to map it.
  static void showError(
    BuildContext context,
    Object error, {
    VoidCallback? onRetry,
  }) {
    final mapped = ErrorMapper.map(error);
    _show(
      context,
      message: mapped.message,
      icon: Icons.error_outline_rounded,
      iconColor: context.palette.danger,
      duration: const Duration(seconds: 6),
      actionLabel: onRetry == null ? null : 'Retry',
      onAction: onRetry,
    );
  }

  /// A validation message, which is the user's to fix rather than a failure.
  static void showValidation(BuildContext context, String message) {
    _show(
      context,
      message: message,
      icon: Icons.warning_amber_rounded,
      iconColor: context.palette.warning,
      duration: const Duration(seconds: 5),
    );
  }

  static void _show(
    BuildContext context, {
    required String message,
    required IconData icon,
    required Color iconColor,
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    // Replace rather than queue: a stack of snackbars makes the most recent
    // message the last one a user sees, which is backwards.
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: duration,
        content: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            AppSpacing.hGapMd,
            Expanded(child: Text(message)),
          ],
        ),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(label: actionLabel, onPressed: onAction)
            : null,
      ),
    );
  }

  /// A confirmation dialog. Returns true only on explicit confirmation.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool isDestructive = false,
    List<String> consequences = const [],
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: context.text.bodyMedium),
            if (consequences.isNotEmpty) ...[
              AppSpacing.gapLg,
              // Spelling out what will happen, because a destructive action on
              // financial records should never be a surprise.
              for (final consequence in consequences)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('•  ', style: context.text.bodyMedium),
                      Expanded(
                        child: Text(consequence, style: context.text.bodyMedium),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: isDestructive
                ? FilledButton.styleFrom(
                    backgroundColor: context.palette.danger,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 44),
                  )
                : FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// A destructive confirmation that requires typing a phrase.
  ///
  /// Reserved for account deletion: a misplaced tap must not be able to erase
  /// someone's financial history.
  static Future<bool> confirmByTyping(
    BuildContext context, {
    required String title,
    required String message,
    required String requiredText,
    String confirmLabel = 'Delete',
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final matches = controller.text.trim().toLowerCase() ==
              requiredText.trim().toLowerCase();
          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: context.text.bodyMedium),
                AppSpacing.gapXl,
                TextField(
                  controller: controller,
                  autofocus: true,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Type $requiredText to confirm',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    matches ? () => Navigator.of(context).pop(true) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: context.palette.danger,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 44),
                ),
                child: Text(confirmLabel),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    return result ?? false;
  }

  /// Runs [action] with a blocking progress overlay, reporting the outcome.
  ///
  /// Returns null when the action failed, so callers can decide whether to close
  /// a form. The error is shown here rather than rethrown into a widget tree.
  static Future<T?> runWithProgress<T>(
    BuildContext context, {
    required Future<T> Function() action,
    String? progressMessage,
    String? successMessage,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    var dialogShown = false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (context) {
        dialogShown = true;
        return _ProgressDialog(message: progressMessage);
      },
    );

    try {
      final result = await action();
      if (dialogShown && navigator.canPop()) navigator.pop();
      if (context.mounted && successMessage != null) {
        showSuccess(context, successMessage);
      }
      return result;
    } on Object catch (error) {
      if (dialogShown && navigator.canPop()) navigator.pop();
      if (context.mounted) showError(context, error);
      return null;
    }
  }

  /// Shows a modal bottom sheet using the app's sheet styling.
  static Future<T?> showSheet<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool isScrollControlled = true,
    bool showDragHandle = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      showDragHandle: showDragHandle,
      useSafeArea: true,
      // Constrained so a long list sheet does not cover the whole screen and
      // leave the user without visible context.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      builder: builder,
    );
  }

  /// Turns a thrown [ValidationException] into inline field errors when it
  /// carries them, or a snackbar when it does not.
  static Map<String, String> fieldErrorsFrom(Object error) {
    final mapped = ErrorMapper.map(error);
    if (mapped is ValidationException) return mapped.fieldErrors;
    return const {};
  }
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            AppSpacing.hGapLg,
            Flexible(
              child: Text(
                message ?? 'Saving…',
                style: context.text.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A banner shown while the device is offline.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.lastUpdated});

  /// When the data on screen was fetched, so the user knows how stale it is.
  final DateTime? lastUpdated;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: context.palette.warning.withValues(alpha: context.isDark ? 0.18 : 0.12),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 16,
            color: context.palette.warning,
          ),
          AppSpacing.hGapSm,
          Expanded(
            child: Text(
              lastUpdated == null
                  ? 'Offline — showing saved data'
                  : 'Offline — saved data from '
                      '${_relative(lastUpdated!)}',
              style: context.text.labelMedium
                  ?.copyWith(color: context.palette.warning),
            ),
          ),
        ],
      ),
    );
  }

  static String _relative(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'moments ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }
}
