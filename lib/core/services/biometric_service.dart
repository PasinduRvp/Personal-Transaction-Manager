import 'package:flutter/services.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';
import 'package:logging/logging.dart';

final _log = Logger('Biometrics');

/// Why a biometric check could not be offered, or did not pass.
///
/// A plain `false` from the plugin covers both "the user pressed cancel" and
/// "this device has no sensor", and those need opposite handling: one is a
/// decision to respect silently, the other means a setting should never have
/// been offered. So the outcome is named rather than boolean.
enum BiometricOutcome {
  /// Verified.
  success,

  /// The user dismissed the prompt. Not an error — no message is shown.
  cancelled,

  /// No sensor, or the OS does not support it.
  unavailable,

  /// Hardware exists but nothing is enrolled, or no device passcode is set.
  notEnrolled,

  /// Too many failed attempts. Temporary.
  lockedOut,

  /// Locked until the device passcode is entered.
  permanentlyLockedOut,

  /// Anything else, including a platform error.
  failed;

  bool get isSuccess => this == BiometricOutcome.success;

  /// Whether this outcome deserves a message. A cancel does not: the user
  /// knows they cancelled, and telling them so reads as a failure.
  bool get isWorthReporting =>
      this != BiometricOutcome.success && this != BiometricOutcome.cancelled;

  /// What to tell the user. Phrased as a state of the device, not a fault of
  /// theirs, and each one says what to do about it.
  String get message => switch (this) {
        BiometricOutcome.success => 'Verified',
        BiometricOutcome.cancelled => 'Cancelled',
        BiometricOutcome.unavailable =>
          'This device does not support biometric unlock.',
        BiometricOutcome.notEnrolled =>
          'Add a fingerprint, face unlock or a screen lock in your device '
              'settings first.',
        BiometricOutcome.lockedOut =>
          'Too many attempts. Wait a moment and try again.',
        BiometricOutcome.permanentlyLockedOut =>
          'Biometric unlock is locked. Unlock your device with its PIN, '
              'pattern or password first.',
        BiometricOutcome.failed => 'Could not verify. Please try again.',
      };
}

/// What the device can do, read once and cached by the provider that holds it.
class BiometricCapability {
  const BiometricCapability({
    required this.isSupported,
    required this.hasEnrolled,
    required this.types,
  });

  const BiometricCapability.none()
      : isSupported = false,
        hasEnrolled = false,
        types = const [];

  /// Whether the hardware and OS can do this at all.
  final bool isSupported;

  /// Whether the user has actually enrolled something to check against.
  final bool hasEnrolled;
  final List<BiometricType> types;

  /// The only state in which the lock is worth offering. Hardware alone is not
  /// enough: a switch that turns on and then cannot verify anybody is worse
  /// than no switch.
  bool get canAuthenticate => isSupported && hasEnrolled;

  /// What to call it on screen. Devices differ, and "Biometric unlock" on a
  /// phone that only does fingerprints is needlessly vague.
  String get label {
    if (types.contains(BiometricType.face)) return 'Face unlock';
    if (types.contains(BiometricType.fingerprint)) return 'Fingerprint';
    if (types.contains(BiometricType.iris)) return 'Iris';
    if (types.contains(BiometricType.strong) ||
        types.contains(BiometricType.weak)) {
      return 'Biometric unlock';
    }
    return 'Device unlock';
  }

  String get icon => types.contains(BiometricType.face) ? 'face' : 'fingerprint';
}

/// The device's biometric prompt.
///
/// Nothing biometric is read, stored or transmitted by this app: the platform
/// keyguard makes the decision against credentials held in hardware, and all
/// that crosses back is a yes or a no. There is correspondingly nothing here
/// to encrypt or to leak — which is the reason to use the system prompt rather
/// than anything resembling an in-app check.
class BiometricService {
  BiometricService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// What this device is capable of.
  ///
  /// Never throws: on a device or platform where the plugin is not implemented
  /// the call raises, and the honest answer to "can you do biometrics" in that
  /// case is no, not a crash on the settings screen.
  Future<BiometricCapability> capability() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return const BiometricCapability.none();

      final canCheck = await _auth.canCheckBiometrics;
      final types = await _auth.getAvailableBiometrics();

      return BiometricCapability(
        isSupported: true,
        // `canCheckBiometrics` is false when nothing is enrolled, but a device
        // passcode still satisfies `authenticate` with `biometricOnly: false`
        // — so a supported device with a screen lock counts as usable.
        hasEnrolled: canCheck || types.isNotEmpty,
        types: types,
      );
    } on Object catch (error, stack) {
      _log.warning('Could not read biometric capability', error, stack);
      return const BiometricCapability.none();
    }
  }

  /// Asks the device to verify the user.
  ///
  /// [reason] is shown in the system prompt, so it says what is being unlocked
  /// rather than naming the app — the user can already see which app is
  /// asking.
  ///
  /// `biometricOnly` is deliberately false: falling back to the device PIN is
  /// the behaviour a user expects from a lock, and refusing it would strand
  /// anyone whose finger is wet or whose face is in the dark.
  Future<BiometricOutcome> authenticate({required String reason}) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          // Survives the app being backgrounded mid-prompt, which is routine:
          // some OEM prompts count as a pause.
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: true,
        ),
      );
      return ok ? BiometricOutcome.success : BiometricOutcome.cancelled;
    } on PlatformException catch (error, stack) {
      final outcome = _outcomeFor(error.code);
      // Logged at warning only when it is a real fault; a device with nothing
      // enrolled is a configuration state, not a problem to report.
      if (outcome == BiometricOutcome.failed) {
        _log.warning('Biometric prompt failed: ${error.code}', error, stack);
      }
      return outcome;
    } on Object catch (error, stack) {
      _log.warning('Biometric prompt failed', error, stack);
      return BiometricOutcome.failed;
    }
  }

  static BiometricOutcome _outcomeFor(String code) => switch (code) {
        auth_error.notAvailable => BiometricOutcome.unavailable,
        auth_error.otherOperatingSystem => BiometricOutcome.unavailable,
        auth_error.biometricOnlyNotSupported => BiometricOutcome.unavailable,
        auth_error.notEnrolled => BiometricOutcome.notEnrolled,
        auth_error.passcodeNotSet => BiometricOutcome.notEnrolled,
        auth_error.lockedOut => BiometricOutcome.lockedOut,
        auth_error.permanentlyLockedOut =>
          BiometricOutcome.permanentlyLockedOut,
        _ => BiometricOutcome.failed,
      };
}
