import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_spacing.dart';

/// Shared chrome for the sign-in, sign-up and recovery screens.
///
/// Content is centred and width-capped so the forms do not stretch across a
/// tablet or a desktop window, where a full-width text field is both ugly and
/// harder to read.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.showBackButton = false,
    this.footer,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool showBackButton;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: showBackButton
          ? AppBar(backgroundColor: Colors.transparent, elevation: 0)
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxl,
              vertical: AppSpacing.xxxl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!showBackButton) ...[
                    const _BrandMark(),
                    AppSpacing.gapXxl,
                  ],
                  Text(title, style: context.text.headlineMedium),
                  AppSpacing.gapSm,
                  Text(subtitle, style: context.text.bodyMedium),
                  AppSpacing.gapXxl,
                  ...children,
                  if (footer != null) ...[
                    AppSpacing.gapXxl,
                    footer!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: context.colors.primary,
            borderRadius: AppRadius.mdAll,
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.account_balance_wallet_rounded,
            color: context.colors.onPrimary,
            size: 24,
          ),
        ),
        AppSpacing.hGapMd,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppConstants.appName,
              style: context.text.titleLarge?.copyWith(letterSpacing: -0.4),
            ),
            Text(
              AppConstants.appTagline,
              style: context.text.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}

/// A password field with a visibility toggle and optional strength meter.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.validator,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
    this.showStrength = false,
    this.autofillHints,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final TextInputAction textInputAction;
  final VoidCallback? onSubmitted;
  final bool showStrength;
  final Iterable<String>? autofillHints;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: widget.controller,
          obscureText: _obscured,
          autofillHints: widget.autofillHints,
          textInputAction: widget.textInputAction,
          validator: widget.validator,
          onFieldSubmitted: (_) => widget.onSubmitted?.call(),
          onChanged: widget.showStrength ? (_) => setState(() {}) : null,
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              icon: Icon(
                _obscured
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: () => setState(() => _obscured = !_obscured),
              tooltip: _obscured ? 'Show password' : 'Hide password',
            ),
          ),
        ),
        if (widget.showStrength && widget.controller.text.isNotEmpty) ...[
          AppSpacing.gapSm,
          _PasswordStrength(password: widget.controller.text),
        ],
      ],
    );
  }
}

/// A rough strength indicator.
///
/// Deliberately advisory: the actual rule is enforced by the validator and by
/// Supabase, and a meter that blocks submission on a subjective score annoys
/// users without making anything safer.
class _PasswordStrength extends StatelessWidget {
  const _PasswordStrength({required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final score = _score(password);
    final (label, color) = switch (score) {
      0 || 1 => ('Weak', context.palette.danger),
      2 => ('Fair', context.palette.warning),
      3 => ('Good', context.palette.info),
      _ => ('Strong', context.palette.success),
    };

    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i < score ? color : context.palette.surfaceAlt,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (i < 3) const SizedBox(width: 4),
        ],
        AppSpacing.hGapMd,
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: context.text.labelSmall
                ?.copyWith(color: color, letterSpacing: 0),
          ),
        ),
      ],
    );
  }

  static int _score(String password) {
    var score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (password.contains(RegExp('[A-Z]')) &&
        password.contains(RegExp('[a-z]'))) {
      score++;
    }
    if (password.contains(RegExp('[0-9]')) &&
        password.contains(RegExp(r'[^A-Za-z0-9]'))) {
      score++;
    }
    return score.clamp(0, 4);
  }
}
