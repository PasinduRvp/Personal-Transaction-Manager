import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/providers/auth_providers.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/providers/security_providers.dart';

/// Covers the app until the user verifies.
///
/// A cover rather than a route: the navigator underneath keeps its stack, so
/// unlocking returns to the screen the user was on instead of the dashboard.
/// It is opaque, which is the point — the task-switcher thumbnail and anyone
/// glancing over should see this, not a balance.
class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key});

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> {
  String? _message;

  @override
  void initState() {
    super.initState();
    // Prompt straight away: an extra tap before the fingerprint reader is
    // pure ceremony. The button below is the retry path, and the only path
    // after a cancel.
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    final status = ref.read(appLockControllerProvider);
    if (status == AppLockStatus.unlocking) return;

    final outcome = await ref.read(appLockControllerProvider.notifier).unlock();
    if (!mounted) return;

    setState(() {
      // A cancel is a decision, not a failure, so it leaves no message behind.
      _message = outcome.isWorthReporting ? outcome.message : null;
    });
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will need your email and password to sign back in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Unlocked first: signing out sends the router to the login screen, and a
    // lock left covering it would trap the user behind a prompt for an account
    // they are no longer in.
    ref.read(appLockControllerProvider.notifier).unlockWithoutPrompt();
    await ref.read(authControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(appLockControllerProvider);
    final capability = ref.watch(biometricCapabilityProvider).valueOrNull;
    final isBusy = status == AppLockStatus.unlocking;

    return Scaffold(
      // Opaque, so nothing shows through while locked.
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: context.colors.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    capability?.icon == 'face'
                        ? Icons.face_retouching_natural_outlined
                        : Icons.fingerprint_rounded,
                    size: 44,
                    color: context.colors.onPrimaryContainer,
                  ),
                ),
                AppSpacing.gapXl,
                Text(
                  '${AppConstants.appName} is locked',
                  style: context.text.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                AppSpacing.gapSm,
                Text(
                  'Verify to see your accounts and transactions.',
                  style: context.text.bodyMedium,
                  textAlign: TextAlign.center,
                ),

                if (_message != null) ...[
                  AppSpacing.gapLg,
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: context.palette.danger.withValues(alpha: 0.12),
                      borderRadius: AppRadius.mdAll,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 18,
                          color: context.palette.danger,
                        ),
                        AppSpacing.hGapSm,
                        Expanded(
                          child: Text(
                            _message!,
                            style: context.text.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                AppSpacing.gapXxl,
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: isBusy ? null : _unlock,
                    icon: isBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.lock_open_rounded),
                    label: Text(isBusy ? 'Waiting…' : 'Unlock'),
                  ),
                ),
                AppSpacing.gapMd,

                // The way out when the sensor will not cooperate at all. A lock
                // with no escape would make a broken reader into a lost account.
                TextButton(
                  onPressed: isBusy ? null : _signOut,
                  child: const Text('Sign out instead'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps the app, applying the lock and the privacy rules that depend on the
/// app's lifecycle.
///
/// One observer for both, because they react to the same events and a second
/// observer would double-handle them.
class SecurityGate extends ConsumerStatefulWidget {
  const SecurityGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SecurityGate> createState() => _SecurityGateState();
}

class _SecurityGateState extends ConsumerState<SecurityGate>
    with WidgetsBindingObserver {
  /// The stored defaults are applied once, on the first load of the settings.
  /// Re-applying them on every settings change would undo whatever the user
  /// had chosen this session each time an unrelated toggle was saved.
  bool _appliedDefaults = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final settings = ref.read(settingsControllerProvider).valueOrNull;
    if (settings == null) return;

    switch (lifecycle) {
      // `inactive` is deliberately not handled: it fires for every system
      // overlay, including the biometric prompt itself, so acting on it would
      // mean re-locking the app during its own unlock.
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        ref.read(appLockControllerProvider.notifier).markLeftForeground();
        ref.read(privacyModeControllerProvider.notifier).hideForBackground();

      case AppLifecycleState.resumed:
        ref.read(appLockControllerProvider.notifier).onResumed(
              lockEnabled: settings.biometricLockEnabled,
              timeoutSeconds: settings.appLockTimeoutSeconds,
            );

      case AppLifecycleState.inactive:
        break;
    }
  }

  /// Applies the stored defaults the first time settings arrive.
  void _applyDefaults(UserSettingsSnapshot snapshot) {
    if (_appliedDefaults) return;
    _appliedDefaults = true;

    ref
        .read(privacyModeControllerProvider.notifier)
        .applyStoredDefault(snapshot.hideAmounts);

    // Locked on arrival, not on the next background: the whole point is that
    // opening the app from cold asks first.
    if (snapshot.lockEnabled) {
      ref.read(appLockControllerProvider.notifier).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final settings = ref.watch(settingsControllerProvider).valueOrNull;
    final status = ref.watch(appLockControllerProvider);

    // Nothing to protect until there is a verified session, and a lock over the
    // login screen would be a dead end.
    if (!auth.canAccessApp) {
      if (status.isLocked) {
        // Signing out while locked clears the lock rather than leaving it to
        // reappear over the next session.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(appLockControllerProvider.notifier).unlockWithoutPrompt();
          }
        });
      }
      _appliedDefaults = false;
      return widget.child;
    }

    if (settings != null) {
      // Deferred to after the frame: this runs during build, and a provider
      // written to mid-build throws.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyDefaults(
          UserSettingsSnapshot(
            hideAmounts: settings.hideAmountsOnDashboard,
            lockEnabled: settings.biometricLockEnabled,
          ),
        );
      });
    }

    return Stack(
      children: [
        widget.child,
        if (status.isLocked)
          // The lock screen's own Scaffold is opaque, so it both covers the
          // screen underneath and swallows taps aimed at it. Wrapping this in
          // an AbsorbPointer would be backwards — that blocks its child, which
          // is the one thing here that must stay tappable.
          const Positioned.fill(child: AppLockScreen()),
      ],
    );
  }
}

/// The two stored flags the gate applies at startup, in one value so the
/// callback has a single argument rather than a positional pair.
class UserSettingsSnapshot {
  const UserSettingsSnapshot({
    required this.hideAmounts,
    required this.lockEnabled,
  });

  final bool hideAmounts;
  final bool lockEnabled;
}
