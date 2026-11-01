import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/services/biometric_service.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/models/profile.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/providers/security_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';

/// Security and privacy: the app lock, and what the eye icon does.
///
/// Every switch here states what it protects against rather than what it
/// technically does. "Hide amounts" is not a feature, it is an answer to
/// someone sitting next to you on a bus, and the subtitles say so.
class PrivacySettingsScreen extends ConsumerWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Security & privacy')),
      body: settings.view(
        (data) => _Body(settings: data),
        onRetry: () => ref.invalidate(settingsControllerProvider),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.settings});

  final UserSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capability = ref.watch(biometricCapabilityProvider);
    final hidden = ref.watch(hideAmountsProvider);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        // ---------------------------------------------------------------
        // App lock
        // ---------------------------------------------------------------
        _GroupHeader(
          title: 'App lock',
          subtitle: 'Ask for your fingerprint or face before Finora opens.',
        ),
        capability.when(
          loading: () => const AppCard(child: CardSkeleton(height: 72)),
          error: (_, __) => const _UnavailableCard(
            message: 'Could not check what this device supports.',
          ),
          data: (device) => device.canAuthenticate
              ? _LockCard(settings: settings, device: device)
              : _UnavailableCard(
                  message: device.isSupported
                      ? 'Add a fingerprint, face unlock or a screen lock in '
                          'your device settings to use the app lock.'
                      : 'This device does not support biometric unlock.',
                ),
        ),
        AppSpacing.gapXl,

        // ---------------------------------------------------------------
        // Hiding amounts
        // ---------------------------------------------------------------
        _GroupHeader(
          title: 'Hide amounts',
          subtitle: 'The eye on the home screen covers every figure in the '
              'app — balances, transactions, budgets and reports.',
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              SwitchListTile(
                value: settings.hideAmountsOnDashboard,
                onChanged: (value) => _setHideAmounts(context, ref, value),
                secondary: _LeadingIcon(
                  settings.hideAmountsOnDashboard
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                title: Text('Start hidden', style: context.text.titleSmall),
                subtitle: Text(
                  'Amounts are covered each time the app opens.',
                  style: context.text.bodySmall,
                ),
              ),
              const Divider(height: 1, indent: AppSpacing.lg),

              SwitchListTile(
                value: settings.autoHideOnBackground,
                onChanged: (value) => ref
                    .read(settingsControllerProvider.notifier)
                    .setAutoHideOnBackground(value),
                secondary: const _LeadingIcon(Icons.layers_clear_outlined),
                title: Text(
                  'Hide when switching apps',
                  style: context.text.titleSmall,
                ),
                subtitle: Text(
                  'Covers amounts when Finora leaves the screen, so they are '
                  'not in the app-switcher preview.',
                  style: context.text.bodySmall,
                ),
              ),
              const Divider(height: 1, indent: AppSpacing.lg),

              SwitchListTile(
                // A reveal check is meaningless without something to check
                // against, so it is switched off and disabled rather than
                // offered as a lock with no key.
                value: settings.requireBiometricToReveal &&
                    ref.watch(canUseBiometricsProvider),
                onChanged: ref.watch(canUseBiometricsProvider)
                    ? (value) => ref
                        .read(settingsControllerProvider.notifier)
                        .setRequireBiometricToReveal(value)
                    : null,
                secondary: const _LeadingIcon(Icons.fingerprint_rounded),
                title: Text(
                  'Verify before revealing',
                  style: context.text.titleSmall,
                ),
                subtitle: Text(
                  ref.watch(canUseBiometricsProvider)
                      ? 'Tapping the eye to show amounts asks for your '
                          'fingerprint or face first.'
                      : 'Needs a fingerprint, face unlock or screen lock on '
                          'this device.',
                  style: context.text.bodySmall,
                ),
              ),
              const Divider(height: 1, indent: AppSpacing.lg),

              _TimeoutRow(
                icon: Icons.timer_outlined,
                title: 'Hide again after',
                value: settings.revealTimeoutSeconds,
                neverLabel: 'Until I hide them',
                options: const [0, 30, 60, 300],
                onChanged: (seconds) => ref
                    .read(settingsControllerProvider.notifier)
                    .setRevealTimeout(seconds),
              ),
            ],
          ),
        ),
        AppSpacing.gapLg,

        // The live state, separate from the stored default, because the two
        // genuinely differ and a settings screen that pretended otherwise
        // would be lying about which one the switch above controls.
        AppCard(
          child: Row(
            children: [
              Icon(
                hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                size: 20,
                color: context.palette.textSecondary,
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: Text(
                  hidden
                      ? 'Amounts are hidden right now.'
                      : 'Amounts are visible right now.',
                  style: context.text.bodyMedium,
                ),
              ),
              TextButton(
                onPressed: () async {
                  final outcome = await ref
                      .read(privacyModeControllerProvider.notifier)
                      .toggle();
                  if (!context.mounted || !outcome.isWorthReporting) return;
                  AppFeedback.showInfo(context, outcome.message);
                },
                child: Text(hidden ? 'Show' : 'Hide'),
              ),
            ],
          ),
        ),

        AppSpacing.gapXl,
        _PrivacyNotes(),
        AppSpacing.gapXl,
      ],
    );
  }

  Future<void> _setHideAmounts(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    final outcome = await ref
        .read(settingsControllerProvider.notifier)
        .setHideAmounts(value);
    if (!context.mounted || !outcome.isWorthReporting) return;
    AppFeedback.showInfo(context, outcome.message);
  }
}

class _LockCard extends ConsumerWidget {
  const _LockCard({required this.settings, required this.device});

  final UserSettings settings;
  final BiometricCapability device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        children: [
          SwitchListTile(
            value: settings.biometricLockEnabled,
            onChanged: (value) => _toggle(context, ref, value),
            secondary: _LeadingIcon(
              device.icon == 'face'
                  ? Icons.face_retouching_natural_outlined
                  : Icons.fingerprint_rounded,
            ),
            title: Text('Require ${device.label}',
                style: context.text.titleSmall),
            subtitle: Text(
              'Finora stays locked until you verify.',
              style: context.text.bodySmall,
            ),
          ),
          if (settings.biometricLockEnabled) ...[
            const Divider(height: 1, indent: AppSpacing.lg),
            _TimeoutRow(
              icon: Icons.lock_clock_outlined,
              title: 'Lock after',
              value: settings.appLockTimeoutSeconds,
              neverLabel: 'Immediately',
              options: const [0, 30, 60, 300, 900],
              // Without a grace period the lock is unusable in practice:
              // picking a receipt from the gallery backgrounds the app, and
              // re-authenticating to return to the form you were already in
              // teaches people to switch the whole thing off.
              helper: 'How long Finora can be in the background before it '
                  'locks again.',
              onChanged: (seconds) => ref
                  .read(settingsControllerProvider.notifier)
                  .setAppLockTimeout(seconds),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool value) async {
    final outcome = await ref
        .read(settingsControllerProvider.notifier)
        .setBiometricLock(value);

    if (!context.mounted) return;
    if (outcome.isSuccess) {
      AppFeedback.showSuccess(
        context,
        value ? 'App lock is on' : 'App lock is off',
      );
      return;
    }
    if (outcome.isWorthReporting) AppFeedback.showError(context, outcome.message);
  }
}

/// One timeout choice, shown as a sheet rather than a dropdown so the options
/// are readable at a glance.
class _TimeoutRow extends StatelessWidget {
  const _TimeoutRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.neverLabel,
    required this.options,
    required this.onChanged,
    this.helper,
  });

  final IconData icon;
  final String title;
  final int value;

  /// What zero means here — "Immediately" for a lock, "Until I hide them" for
  /// a reveal. The same number means opposite things in the two places.
  final String neverLabel;
  final List<int> options;
  final String? helper;
  final ValueChanged<int> onChanged;

  String _labelFor(int seconds) {
    if (seconds <= 0) return neverLabel;
    if (seconds < 60) return '$seconds seconds';
    final minutes = seconds ~/ 60;
    return minutes == 1 ? '1 minute' : '$minutes minutes';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _LeadingIcon(icon),
      title: Text(title, style: context.text.titleSmall),
      subtitle: helper == null ? null : Text(helper!, style: context.text.bodySmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_labelFor(value), style: context.text.bodyMedium),
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: context.palette.textTertiary,
          ),
        ],
      ),
      onTap: () async {
        final picked = await AppFeedback.showSheet<int>(
          context,
          builder: (context) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    0,
                    AppSpacing.xl,
                    AppSpacing.sm,
                  ),
                  child: Text(title, style: context.text.titleLarge),
                ),
                const Divider(height: 1),
                for (final option in options)
                  ListTile(
                    title: Text(_labelFor(option),
                        style: context.text.titleSmall),
                    trailing: option == value
                        ? Icon(Icons.check_rounded,
                            color: context.colors.primary)
                        : null,
                    onTap: () => Navigator.of(context).pop(option),
                  ),
              ],
            ),
          ),
        );
        if (picked != null && picked != value) onChanged(picked);
      },
    );
  }
}

class _UnavailableCard extends StatelessWidget {
  const _UnavailableCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: context.palette.textSecondary,
          ),
          AppSpacing.hGapMd,
          Expanded(child: Text(message, style: context.text.bodySmall)),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        bottom: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: context.text.labelSmall
                ?.copyWith(color: context.palette.textSecondary),
          ),
          AppSpacing.gapXs,
          Text(subtitle, style: context.text.bodySmall),
        ],
      ),
    );
  }
}

class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Icon(icon, size: 22, color: context.palette.textSecondary);
  }
}

/// What these settings do and do not protect against.
///
/// Stated plainly because the honest limits matter: the app lock covers the
/// app, not the device, and someone with the unlocked phone and the password
/// can still sign in fresh.
class _PrivacyNotes extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppCard(
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
              Text('What this covers', style: context.text.titleSmall),
            ],
          ),
          AppSpacing.gapMd,
          for (final point in const [
            'Your fingerprint or face never reaches Finora. Your device '
                'checks it and returns only a yes or a no.',
            'Hiding amounts covers what is on screen. It does not encrypt '
                'anything, and the figures are still on the device.',
            'The app lock protects this app, not your device. Someone with '
                'your password can still sign in on another phone.',
            'Finora never stores banking passwords, full card numbers or '
                'CVVs.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: context.text.bodySmall),
                  Expanded(child: Text(point, style: context.text.bodySmall)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
