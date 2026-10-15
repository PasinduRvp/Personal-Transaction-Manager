import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/providers/auth_providers.dart';
import '../../../shared/widgets/feedback.dart';
import 'auth_scaffold.dart';

/// Requests a password reset email.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isSubmitting = false;
  bool _isSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.hideKeyboard();

    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .sendPasswordReset(_emailController.text);
      // Shown whatever the server said about the address. Confirming whether an
      // email is registered would turn this screen into an account-existence
      // oracle for anyone who found it.
      if (mounted) setState(() => _isSent = true);
    } on Object catch (error) {
      if (mounted) AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isSent) {
      return AuthScaffold(
        title: 'Check your inbox',
        subtitle: 'If an account exists for '
            '${_emailController.text.trim()}, we have sent a link to reset '
            'your password. It expires in one hour.',
        showBackButton: true,
        children: [
          AppSpacing.gapLg,
          FilledButton(
            onPressed: () => context.go(AppRoutes.login),
            child: const Text('Back to sign in'),
          ),
          AppSpacing.gapSm,
          TextButton(
            onPressed: () => setState(() => _isSent = false),
            child: const Text('Use a different email'),
          ),
        ],
      );
    }

    return AuthScaffold(
      title: 'Reset your password',
      subtitle: 'Enter your email address and we will send you a link to set a '
          'new password.',
      showBackButton: true,
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofocus: true,
                validator: Validators.email,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
              ),
              AppSpacing.gapXl,
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
                    : const Text('Send reset link'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Changes the password of the signed-in user.
///
/// Not reached from the emailed recovery link: Firebase completes a reset on its
/// own hosted page, so by the time a user who forgot their password is back in
/// the app they already have a working one. This screen is the deliberate
/// change-it-now path from Settings, which is why it asks for the current
/// password — that is also what satisfies Firebase's recent-login requirement.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _currentController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.hideKeyboard();

    setState(() => _isSubmitting = true);
    try {
      await ref.read(authControllerProvider.notifier).changePassword(
            currentPassword: _currentController.text,
            newPassword: _passwordController.text,
          );

      if (!mounted) return;
      AppFeedback.showSuccess(context, 'Your password has been updated.');
      context.go(AppRoutes.home);
    } on Object catch (error) {
      if (mounted) AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Change your password',
      subtitle: 'Choose a password you have not used before.',
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PasswordField(
                controller: _currentController,
                label: 'Current password',
                textInputAction: TextInputAction.next,
                validator: (value) => (value == null || value.isEmpty)
                    ? 'Enter your current password.'
                    : null,
              ),
              AppSpacing.gapLg,
              PasswordField(
                controller: _passwordController,
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
                  _passwordController.text,
                ),
                onSubmitted: _submit,
              ),
              AppSpacing.gapXl,
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
                    : const Text('Update password'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Waits for the user to confirm their email address.
///
/// Polls rather than requiring the user to restart the app: they tap the link in
/// their mail client and come back, and the screen notices.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, this.email});

  final String? email;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _isChecking = false;
  bool _isResending = false;
  DateTime? _lastResend;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A slow poll as a fallback; the resume check below is what usually fires.
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the mail app is the moment verification is most likely to
    // have just happened.
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check({bool showFeedback = false}) async {
    if (_isChecking || !mounted) return;
    setState(() => _isChecking = true);

    try {
      final verified =
          await ref.read(authControllerProvider.notifier).refreshVerification();

      if (!mounted) return;
      if (verified) {
        _timer?.cancel();
        context.go(AppRoutes.home);
      } else if (showFeedback) {
        AppFeedback.showInfo(
          context,
          'Not verified yet. Open the link in the email we sent you.',
        );
      }
    } on Object catch (error) {
      if (mounted && showFeedback) AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _resend() async {
    final email = widget.email ?? ref.read(authControllerProvider).email;
    if (email == null) return;

    // Supabase rate-limits these; a local cooldown avoids the user hitting it.
    final last = _lastResend;
    if (last != null && DateTime.now().difference(last).inSeconds < 60) {
      final remaining = 60 - DateTime.now().difference(last).inSeconds;
      AppFeedback.showInfo(
        context,
        'Please wait $remaining seconds before sending another email.',
      );
      return;
    }

    setState(() => _isResending = true);
    try {
      await ref.read(authControllerProvider.notifier).resendVerification(email);
      _lastResend = DateTime.now();
      if (mounted) {
        AppFeedback.showSuccess(context, 'Verification email sent.');
      }
    } on Object catch (error) {
      if (mounted) AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.email ?? ref.watch(authControllerProvider).email ?? '';

    return AuthScaffold(
      title: 'Verify your email',
      subtitle: 'We sent a confirmation link to $email. Open it to activate '
          'your account.',
      children: [
        AppSpacing.gapLg,
        FilledButton.icon(
          onPressed: _isChecking ? null : () => _check(showFeedback: true),
          icon: _isChecking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_rounded, size: 20),
          label: Text(_isChecking ? 'Checking…' : "I've verified my email"),
        ),
        AppSpacing.gapSm,
        OutlinedButton.icon(
          onPressed: _isResending ? null : _resend,
          icon: const Icon(Icons.mail_outline_rounded, size: 18),
          label: const Text('Resend email'),
        ),
        AppSpacing.gapLg,
        Center(
          child: TextButton(
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).signOut();
              if (context.mounted) context.go(AppRoutes.login);
            },
            child: const Text('Use a different account'),
          ),
        ),
        AppSpacing.gapXl,
        Text(
          "Can't find the email? Check your spam folder, and make sure "
          '$email is spelled correctly.',
          style: context.text.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// The first frame, shown while the stored session is restored.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
            AppSpacing.gapXl,
            Text('Finora', style: context.text.headlineSmall),
            AppSpacing.gapXxl,
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the app was built without its Supabase configuration.
///
/// A dedicated screen rather than a crash, because the most likely person to see
/// it is a developer who forgot a `--dart-define`, and a clear message saves
/// them a debugging session.
class ConfigurationErrorScreen extends StatelessWidget {
  const ConfigurationErrorScreen({super.key, required this.missing});

  final String missing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.settings_outlined,
                size: 48,
                color: context.palette.warning,
              ),
              AppSpacing.gapXl,
              Text(
                'Configuration needed',
                style: context.text.titleLarge,
                textAlign: TextAlign.center,
              ),
              AppSpacing.gapMd,
              Text(
                'Finora could not start because these values are missing: '
                '$missing.',
                style: context.text.bodyMedium,
                textAlign: TextAlign.center,
              ),
              AppSpacing.gapLg,
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: context.palette.surfaceAlt,
                  borderRadius: AppRadius.mdAll,
                ),
                child: Text(
                  'flutter run \\\n'
                  '  --dart-define=SUPABASE_URL=... \\\n'
                  '  --dart-define=SUPABASE_ANON_KEY=...',
                  style: context.text.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['Courier New'],
                  ),
                ),
              ),
              AppSpacing.gapLg,
              Text(
                'See docs/setup.md for the full list.',
                style: context.text.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
