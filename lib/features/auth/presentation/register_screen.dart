import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/currencies.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/providers/auth_providers.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/pickers.dart';
import 'auth_scaffold.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  String _currency = Currencies.fallback.code;
  bool _acceptedTerms = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (!_acceptedTerms) {
      AppFeedback.showValidation(
        context,
        'Please accept the terms and privacy policy to continue.',
      );
      return;
    }

    context.hideKeyboard();
    setState(() => _isSubmitting = true);

    try {
      await ref.read(authControllerProvider.notifier).signUp(
            email: _emailController.text,
            fullName: _nameController.text,
            password: _passwordController.text,
            defaultCurrency: _currency,
          );

      if (!mounted) return;
      // With email confirmation on, sign-up yields no session, so the router
      // will not move by itself. Send the user to the verification screen.
      context.go(
        '${AppRoutes.verifyEmail}?email='
        '${Uri.encodeComponent(_emailController.text.trim())}',
      );
    } on Object catch (error) {
      if (mounted) AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Create your account',
      subtitle: 'Track your income, spending and savings in one place.',
      showBackButton: true,
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Already have an account?', style: context.text.bodyMedium),
          TextButton(
            onPressed: _isSubmitting ? null : () => context.go(AppRoutes.login),
            child: const Text('Sign in'),
          ),
        ],
      ),
      children: [
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  validator: Validators.fullName,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                AppSpacing.gapLg,
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  validator: Validators.email,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
                ),
                AppSpacing.gapLg,
                PickerField(
                  label: 'Default currency',
                  value: '$_currency · ${Currencies.byCode(_currency).name}',
                  leading: Text(
                    Currencies.byCode(_currency).symbol,
                    style: context.text.titleMedium,
                  ),
                  onTap: () async {
                    final picked = await CurrencyPicker.show(
                      context,
                      selectedCode: _currency,
                    );
                    if (picked != null) {
                      setState(() => _currency = picked.code);
                    }
                  },
                ),
                AppSpacing.gapLg,
                PasswordField(
                  controller: _passwordController,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: Validators.password,
                  showStrength: true,
                ),
                AppSpacing.gapLg,
                PasswordField(
                  controller: _confirmController,
                  label: 'Confirm password',
                  autofillHints: const [AutofillHints.newPassword],
                  validator: (value) => Validators.confirmPassword(
                    value,
                    _passwordController.text,
                  ),
                  onSubmitted: _submit,
                ),
                AppSpacing.gapLg,
                _TermsCheckbox(
                  value: _acceptedTerms,
                  onChanged: (value) =>
                      setState(() => _acceptedTerms = value ?? false),
                ),
                AppSpacing.gapLg,
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
                      : const Text('Create account'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TermsCheckbox extends StatelessWidget {
  const _TermsCheckbox({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        AppSpacing.hGapMd,
        Expanded(
          child: GestureDetector(
            onTap: () => onChanged(!value),
            child: Text(
              'I agree to the Terms of Service and the Privacy Policy.',
              style: context.text.bodySmall,
            ),
          ),
        ),
      ],
    );
  }
}
