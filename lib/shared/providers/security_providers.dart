import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/biometric_service.dart';
import 'profile_providers.dart';

/// The device prompt. One instance: the plugin holds a platform channel, and a
/// second prompt opened over the first is rejected by the OS.
final biometricServiceProvider =
    Provider<BiometricService>((ref) => BiometricService());

/// What this device can actually do.
///
/// Read once and cached. A settings screen that re-queried on every rebuild
/// would flicker its switches between enabled and disabled while the platform
/// answered.
final biometricCapabilityProvider =
    FutureProvider<BiometricCapability>((ref) async {
  return ref.watch(biometricServiceProvider).capability();
});

/// Convenience for the settings screen: whether a lock is worth offering.
final canUseBiometricsProvider = Provider<bool>((ref) {
  return ref.watch(biometricCapabilityProvider).maybeWhen(
        data: (capability) => capability.canAuthenticate,
        orElse: () => false,
      );
});

// ---------------------------------------------------------------------------
// Privacy mode
// ---------------------------------------------------------------------------

/// Whether financial figures are currently hidden, for this session.
///
/// Session state rather than a stored field, for two reasons. Tapping the eye
/// should not cost a Firestore write, and hiding is a thing you do *now* —
/// having it survive to the next launch regardless of the stored default would
/// surprise someone who only wanted to cover the screen on a bus.
/// [UserSettings.hideAmountsOnDashboard] remains the default this starts from,
/// applied by the security gate once settings have loaded.
///
/// [build] deliberately touches nothing: it returns a plain `false` without
/// reading settings or auth, so a widget test can render a [MoneyText] inside a
/// bare `ProviderScope` without Firebase being initialised.
class PrivacyModeController extends Notifier<bool> {
  Timer? _revealTimer;

  /// Guards against the stored default being re-applied after the user has
  /// made their own choice this session.
  bool _defaultApplied = false;

  @override
  bool build() {
    ref.onDispose(_cancelTimer);
    return false;
  }

  void _cancelTimer() {
    _revealTimer?.cancel();
    _revealTimer = null;
  }

  /// Applies the stored default, once per session.
  void applyStoredDefault(bool hidden) {
    if (_defaultApplied) return;
    _defaultApplied = true;
    _cancelTimer();
    state = hidden;
  }

  /// Hides the figures. Never asks for anything: covering up is always allowed,
  /// and a lock you cannot engage without authenticating is not a privacy
  /// feature.
  void hide() {
    _cancelTimer();
    state = true;
  }

  /// Re-hides when the app leaves the foreground, so the figures are not in the
  /// task-switcher thumbnail. Does nothing when the user has switched that off.
  void hideForBackground() {
    final settings = ref.read(settingsControllerProvider).valueOrNull;
    if (settings?.autoHideOnBackground ?? true) hide();
  }

  /// Reveals the figures, asking for a fingerprint or face first when the user
  /// has required one.
  ///
  /// Returns the outcome rather than a bool so the caller can tell a cancel
  /// (say nothing) from a device with nothing enrolled (say what to do).
  Future<BiometricOutcome> reveal() async {
    if (!state) return BiometricOutcome.success;

    final settings = ref.read(settingsControllerProvider).valueOrNull;
    final needsCheck = settings?.requireBiometricToReveal ?? false;

    if (needsCheck) {
      // Capability is re-read rather than trusted from the cache: a user can
      // remove their fingerprint between opening the app and tapping the eye,
      // and the honest result then is "nothing is enrolled", not a silent
      // reveal.
      final capability =
          await ref.read(biometricServiceProvider).capability();

      if (!capability.canAuthenticate) {
        // Fail closed. The setting says a check is required, and the device
        // cannot perform one, so the figures stay hidden — revealing them
        // because the lock is broken would defeat the point of the setting.
        return BiometricOutcome.notEnrolled;
      }

      final outcome = await ref.read(biometricServiceProvider).authenticate(
            reason: 'Verify to show your balances',
          );
      if (!outcome.isSuccess) return outcome;
    }

    _cancelTimer();
    state = false;
    _startRevealTimeout(settings?.revealTimeoutSeconds ?? 0);
    return BiometricOutcome.success;
  }

  /// Re-hides after the chosen interval. Zero means the user hides manually.
  void _startRevealTimeout(int seconds) {
    if (seconds <= 0) return;
    _revealTimer = Timer(Duration(seconds: seconds), () {
      // Guard: the controller may have been disposed, or the user may have
      // hidden the figures already, between the timer firing and this running.
      if (!state) state = true;
    });
  }

  /// The eye button. Hiding is immediate; revealing may be refused.
  Future<BiometricOutcome> toggle() async {
    if (state) return reveal();
    hide();
    return BiometricOutcome.success;
  }
}

final privacyModeControllerProvider =
    NotifierProvider<PrivacyModeController, bool>(PrivacyModeController.new);

// ---------------------------------------------------------------------------
// App lock
// ---------------------------------------------------------------------------

enum AppLockStatus {
  /// The app is usable.
  unlocked,

  /// The lock screen is covering everything.
  locked,

  /// A prompt is on screen. Held separately so the unlock button can show
  /// progress and cannot be pressed twice — a second prompt over the first is
  /// rejected by the platform.
  unlocking;

  bool get isLocked => this != AppLockStatus.unlocked;
}

/// Whether the app is behind its biometric lock.
///
/// Like [PrivacyModeController], [build] returns a safe constant and reads
/// nothing, so nothing in a test or a cold start depends on it.
class AppLockController extends Notifier<AppLockStatus> {
  /// When the app was last backgrounded, for the grace period.
  DateTime? _leftAt;

  @override
  AppLockStatus build() => AppLockStatus.unlocked;

  /// Locks immediately. Called when the lock is first switched on, and on
  /// resume once the grace period has passed.
  void lock() {
    if (state == AppLockStatus.locked) return;
    state = AppLockStatus.locked;
  }

  void unlockWithoutPrompt() {
    _leftAt = null;
    state = AppLockStatus.unlocked;
  }

  void markLeftForeground() => _leftAt = DateTime.now();

  /// Decides whether returning to the foreground should re-lock.
  ///
  /// The grace period exists because an immediate lock is unusable in practice:
  /// picking a receipt from the gallery backgrounds the app, and being asked to
  /// re-authenticate to return to the form you were already filling in teaches
  /// people to switch the feature off entirely.
  void onResumed({required bool lockEnabled, required int timeoutSeconds}) {
    final leftAt = _leftAt;
    _leftAt = null;

    if (!lockEnabled || leftAt == null) return;
    final away = DateTime.now().difference(leftAt);
    if (away.inSeconds >= timeoutSeconds) lock();
  }

  /// Shows the prompt. Returns the outcome so the lock screen can explain a
  /// failure without inventing one for a cancel.
  Future<BiometricOutcome> unlock() async {
    if (state == AppLockStatus.unlocking) return BiometricOutcome.cancelled;
    state = AppLockStatus.unlocking;

    try {
      final outcome = await ref.read(biometricServiceProvider).authenticate(
            reason: 'Unlock Finora',
          );

      if (outcome.isSuccess) {
        _leftAt = null;
        state = AppLockStatus.unlocked;
      } else {
        state = AppLockStatus.locked;
      }
      return outcome;
    } on Object {
      state = AppLockStatus.locked;
      rethrow;
    }
  }
}

final appLockControllerProvider =
    NotifierProvider<AppLockController, AppLockStatus>(AppLockController.new);
