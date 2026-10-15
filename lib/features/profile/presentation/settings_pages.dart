import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/enums.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/providers/auth_providers.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/providers/repository_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../../auth/presentation/auth_scaffold.dart';

/// Which notifications the user wants.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: settings.view(
        (data) => ListView(
          padding: const EdgeInsets.all(AppSpacing.page),
          children: [
            Text(
              'Choose what Finora tells you about. Turning one off stops it '
              'being created at all, not just hidden.',
              style: context.text.bodySmall,
            ),
            AppSpacing.gapXl,

            AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Column(
                children: [
                  for (final kind in const [
                    NotificationKind.budgetWarning,
                    NotificationKind.budgetExceeded,
                    NotificationKind.billDue,
                    NotificationKind.subscriptionRenewal,
                    NotificationKind.recurringDue,
                    NotificationKind.ocrCompleted,
                    NotificationKind.ocrFailed,
                  ]) ...[
                    SwitchListTile(
                      value: data.isEnabled(kind),
                      onChanged: (value) =>
                          controller.setNotification(kind, value),
                      title: Text(kind.label, style: context.text.titleSmall),
                      subtitle: Text(
                        _descriptionFor(kind),
                        style: context.text.bodySmall,
                      ),
                    ),
                    if (kind != NotificationKind.ocrFailed)
                      const Divider(height: 1, indent: AppSpacing.lg),
                  ],
                ],
              ),
            ),
          ],
        ),
        onRetry: () => ref.invalidate(settingsControllerProvider),
      ),
    );
  }

  static String _descriptionFor(NotificationKind kind) => switch (kind) {
        NotificationKind.budgetWarning =>
          'When spending reaches your chosen threshold',
        NotificationKind.budgetExceeded => 'When a budget is fully spent',
        NotificationKind.billDue => 'Before a bill is due, and when overdue',
        NotificationKind.subscriptionRenewal =>
          'Before a subscription renews',
        NotificationKind.recurringDue =>
          'When a recurring transaction needs confirming',
        NotificationKind.ocrCompleted =>
          'When a document has been read and is ready to review',
        NotificationKind.ocrFailed => 'When a document could not be read',
        NotificationKind.goalReached => 'When a savings goal is reached',
        NotificationKind.creditCardDue =>
          'Before a credit card payment is due',
      };
}

/// Password and session.
class SecuritySettingsScreen extends ConsumerStatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  ConsumerState<SecuritySettingsScreen> createState() =>
      _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState
    extends ConsumerState<SecuritySettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.hideKeyboard();

    setState(() => _isSubmitting = true);
    try {
      // The current password is verified first. Supabase would let a valid
      // session change the password without it, but a stolen unlocked phone
      // should not be enough to lock the owner out of their own finances.
      final valid = await ref
          .read(authControllerProvider.notifier)
          .verifyPassword(_currentController.text);

      if (!valid) {
        if (mounted) {
          AppFeedback.showValidation(
            context,
            'That current password is not correct.',
          );
        }
        return;
      }

      await ref
          .read(authRepositoryProvider)
          .updatePassword(_newController.text);

      if (!mounted) return;
      _currentController.clear();
      _newController.clear();
      _confirmController.clear();
      AppFeedback.showSuccess(context, 'Password updated');
    } on Object catch (error) {
      if (mounted) AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(authControllerProvider).email ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.page),
            children: [
              AppSectionCard(
                title: 'Signed in as',
                icon: Icons.person_outline_rounded,
                child: Text(email, style: context.text.bodyLarge),
              ),
              AppSpacing.gapLg,

              AppSectionCard(
                title: 'Change password',
                icon: Icons.lock_outline_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PasswordField(
                      controller: _currentController,
                      label: 'Current password',
                      textInputAction: TextInputAction.next,
                      validator: (value) => Validators.required(
                        value,
                        field: 'Current password',
                      ),
                    ),
                    AppSpacing.gapLg,
                    PasswordField(
                      controller: _newController,
                      label: 'New password',
                      textInputAction: TextInputAction.next,
                      validator: Validators.password,
                      showStrength: true,
                    ),
                    AppSpacing.gapLg,
                    PasswordField(
                      controller: _confirmController,
                      label: 'Confirm new password',
                      validator: (value) => Validators.confirmPassword(
                        value,
                        _newController.text,
                      ),
                      onSubmitted: _changePassword,
                    ),
                    AppSpacing.gapXl,
                    FilledButton(
                      onPressed: _isSubmitting ? null : _changePassword,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Update password'),
                    ),
                  ],
                ),
              ),
              AppSpacing.gapLg,

              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 18,
                          color: context.palette.income,
                        ),
                        AppSpacing.hGapSm,
                        Text(
                          'How your data is protected',
                          style: context.text.titleSmall,
                        ),
                      ],
                    ),
                    AppSpacing.gapMd,
                    for (final point in const [
                      'Your session is kept in your device keychain, not in '
                          'plain storage.',
                      'Every request is checked against database rules that '
                          'only let you read your own rows.',
                      'Documents are stored privately and opened through links '
                          'that expire within minutes.',
                      'Finora never stores banking passwords, full card '
                          'numbers or CVVs.',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('•  ', style: context.text.bodySmall),
                            Expanded(
                              child: Text(point, style: context.text.bodySmall),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Export and account deletion.
class DataSettingsScreen extends ConsumerStatefulWidget {
  const DataSettingsScreen({super.key});

  @override
  ConsumerState<DataSettingsScreen> createState() =>
      _DataSettingsScreenState();
}

class _DataSettingsScreenState extends ConsumerState<DataSettingsScreen> {
  bool _isExporting = false;

  Future<void> _export() async {
    setState(() => _isExporting = true);
    try {
      final data = await ref.read(profileRepositoryProvider).exportData();
      final json = const JsonEncoder.withIndent('  ').convert(data);

      if (!mounted) return;
      // Copied to the clipboard rather than shared as a file: the export is
      // JSON, and a user asking for their data usually wants to paste it
      // somewhere rather than open it.
      await Clipboard.setData(ClipboardData(text: json));

      if (!mounted) return;
      AppFeedback.showSuccess(
        context,
        'Your data has been copied to the clipboard '
        '(${(json.length / 1024).toStringAsFixed(0)} KB)',
      );
    } on Object catch (error) {
      if (mounted) AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _clearData() async {
    final email = ref.read(authControllerProvider).email;
    if (email == null) return;

    final confirmed = await AppFeedback.confirmByTyping(
      context,
      title: 'Clear all data?',
      message: 'This permanently removes your transactions, accounts, budgets, '
          'documents and everything else, but keeps your sign-in active. '
          'It cannot be undone.',
      requiredText: email,
      confirmLabel: 'Clear data',
    );
    if (!confirmed || !mounted) return;

    final done = await AppFeedback.runWithProgress(
      context,
      progressMessage: 'Clearing your data…',
      action: () async {
        await ref.read(profileRepositoryProvider).deleteData();
        return true;
      },
    );

    if (done == true && mounted) {
      AppFeedback.showSuccess(context, 'Data cleared. Please sign in again.');
      // Give the snackbar a moment to appear before we rip the UI away
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        await ref.read(authControllerProvider.notifier).signOut();
      }
    }
  }

  Future<void> _deleteAccount() async {
    final email = ref.read(authControllerProvider).email;
    if (email == null) return;

    final confirmed = await AppFeedback.confirmByTyping(
      context,
      title: 'Delete your account?',
      message: 'This permanently removes your transactions, accounts, budgets, '
          'documents and everything else. It cannot be undone.',
      requiredText: email,
      confirmLabel: 'Delete everything',
    );
    if (!confirmed || !mounted) return;

    final done = await AppFeedback.runWithProgress(
      context,
      progressMessage: 'Deleting your account…',
      action: () async {
        // Deleting the Firebase user needs the Admin SDK, which must never be in
        // a client, so the destructive step runs in a Cloud Function. It also
        // sweeps the user's Firestore documents and storage objects, which
        // Firebase does not cascade on its own.
        await ref.read(profileRepositoryProvider).deleteAccountCompletely(
              confirmEmail: email,
            );
        return true;
      },
    );

    if (done != true || !mounted) return;

    await ref.read(authControllerProvider.notifier).signOut();
    if (mounted) context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your data')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.page),
          children: [
            AppSectionCard(
              title: 'Export your data',
              subtitle: 'Everything Finora holds about you, as JSON',
              icon: Icons.download_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Includes your profile, accounts, categories, '
                    'transactions, budgets, goals, bills, subscriptions and '
                    'document records.',
                    style: context.text.bodySmall,
                  ),
                  AppSpacing.gapLg,
                  OutlinedButton.icon(
                    onPressed: _isExporting ? null : _export,
                    icon: _isExporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.copy_all_outlined, size: 18),
                    label: Text(_isExporting ? 'Preparing…' : 'Copy my data'),
                  ),
                  AppSpacing.gapSm,
                  OutlinedButton.icon(
                    onPressed: () => context.push(AppRoutes.reports),
                    icon: const Icon(Icons.table_chart_outlined, size: 18),
                    label: const Text('Export transactions as CSV or PDF'),
                  ),
                ],
              ),
            ),
            AppSpacing.gapLg,

            AppSectionCard(
              title: 'Storage',
              icon: Icons.cloud_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Documents are kept in private storage. Deleting a document '
                    'removes the file and its extracted text, but keeps any '
                    'transactions you created from it.',
                    style: context.text.bodySmall,
                  ),
                  AppSpacing.gapLg,
                  OutlinedButton.icon(
                    onPressed: () => context.push(AppRoutes.documents),
                    icon: const Icon(Icons.folder_outlined, size: 18),
                    label: const Text('Manage documents'),
                  ),
                ],
              ),
            ),
            AppSpacing.gapLg,

            AppCard(
              borderColor: context.palette.danger.withValues(alpha: 0.4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 20,
                        color: context.palette.danger,
                      ),
                      AppSpacing.hGapMd,
                      Text(
                        'Danger zone',
                        style: context.text.titleMedium
                            ?.copyWith(color: context.palette.danger),
                      ),
                    ],
                  ),
                  AppSpacing.gapMd,
                  Text(
                    'Clear all your data to start fresh, or permanently remove your account. '
                    'Export anything you want to keep first.',
                    style: context.text.bodySmall,
                  ),
                  AppSpacing.gapLg,
                  OutlinedButton(
                    onPressed: _clearData,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.palette.danger,
                      side: BorderSide(
                        color: context.palette.danger.withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Text('Clear all data'),
                  ),
                  AppSpacing.gapSm,
                  OutlinedButton(
                    onPressed: _deleteAccount,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.palette.danger,
                      side: BorderSide(
                        color: context.palette.danger.withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Text('Delete my account'),
                  ),
                ],
              ),
            ),
            AppSpacing.gapXl,
          ],
        ),
      ),
    );
  }
}

/// About.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.page),
          children: [
            Center(
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: context.colors.primary,
                      borderRadius: AppRadius.lgAll,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.account_balance_wallet_rounded,
                      color: context.colors.onPrimary,
                      size: 34,
                    ),
                  ),
                  AppSpacing.gapLg,
                  Text(AppConstants.appName, style: context.text.headlineSmall),
                  Text(
                    AppConstants.appTagline,
                    style: context.text.bodyMedium,
                  ),
                  AppSpacing.gapXs,
                  Text('Version 1.0.0', style: context.text.bodySmall),
                ],
              ),
            ),
            AppSpacing.gapXxl,

            AppSectionCard(
              title: 'What Finora does',
              icon: Icons.info_outline_rounded,
              child: Text(
                'Finora tracks your income, spending, budgets and savings, and '
                'can read receipts and bank statements so you do not have to '
                'type them in. Anything it reads is shown to you for review '
                'before it becomes a transaction — the app never records a '
                'financial figure you have not approved.',
                style: context.text.bodyMedium,
              ),
            ),
            AppSpacing.gapLg,

            AppSectionCard(
              title: 'Built with',
              icon: Icons.code_rounded,
              child: Column(
                children: [
                  for (final entry in const [
                    ('Flutter', 'Mobile, web and desktop UI'),
                    ('Supabase', 'PostgreSQL, authentication and storage'),
                    ('Riverpod', 'State management'),
                    ('fl_chart', 'Charts'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.$1,
                              style: context.text.titleSmall,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              entry.$2,
                              style: context.text.bodySmall,
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Privacy.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.page),
          children: [
            for (final section in const [
              (
                'What Finora stores',
                'Your profile, the accounts and categories you create, the '
                    'transactions you record, and any documents you upload. '
                    'Nothing else.',
              ),
              (
                'What Finora never stores',
                'Banking passwords, full card numbers, CVV codes, or '
                    'credentials for any other service. When you add a card you '
                    'may enter its last four digits, and only those.',
              ),
              (
                'Who can see your data',
                'Only you. The database enforces this with row-level rules, so '
                    'a request for someone else\'s data is refused by the '
                    'server rather than filtered by the app.',
              ),
              (
                'Documents you upload',
                'Stored in private buckets, in a folder that only your account '
                    'can reach. The app opens them through links that expire '
                    'after a few minutes, and there is no public URL.',
              ),
              (
                'Reading documents',
                'When you import a receipt or statement it is sent to a '
                    'document-reading service to extract its text. The original '
                    'text is kept so you can check what was read. Provider '
                    'credentials live on the server and never in the app.',
              ),
              (
                'Your control',
                'You can export everything as JSON, download transactions as '
                    'CSV or PDF, delete individual documents, and delete your '
                    'account entirely.',
              ),
            ]) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(section.$1, style: context.text.titleSmall),
                      AppSpacing.gapSm,
                      Text(section.$2, style: context.text.bodyMedium),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
