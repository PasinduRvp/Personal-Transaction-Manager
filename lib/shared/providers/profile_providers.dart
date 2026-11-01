import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/enums.dart';
import '../../core/services/biometric_service.dart';
import '../models/profile.dart';
import 'auth_providers.dart';
import 'repository_providers.dart';
// Mutual import with this file, which is legal and safe here: Riverpod
// providers are lazy, so neither library needs the other's value at load time.
import 'security_providers.dart';

/// The signed-in user's profile.
///
/// Watches [currentUserIdProvider], so signing into a different account on the
/// same device discards the previous profile rather than briefly showing the
/// wrong person's name and currency.
class ProfileController extends AsyncNotifier<Profile> {
  @override
  Future<Profile> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) {
      throw StateError('No signed-in user');
    }
    return ref.watch(profileRepositoryProvider).fetch();
  }

  Future<void> updateDetails({
    String? fullName,
    String? defaultCurrency,
    String? language,
    String? timezone,
  }) async {
    final current = state.requireValue;
    final updated = current.copyWith(
      fullName: fullName,
      defaultCurrency: defaultCurrency,
      language: language,
      timezone: timezone,
    );

    state = const AsyncValue<Profile>.loading();
    state = await AsyncValue.guard(
      () => ref.read(profileRepositoryProvider).update(updated),
    );
  }

  /// Changes the theme.
  ///
  /// Applied optimistically so the UI switches on the same frame the user taps;
  /// a failed save reverts and surfaces the error rather than leaving the app in
  /// a theme the server does not know about.
  Future<void> setThemeMode(AppThemeMode mode) async {
    final current = state.valueOrNull;
    if (current == null) return;

    state = AsyncValue.data(current.copyWith(themeMode: mode));
    try {
      final saved = await ref
          .read(profileRepositoryProvider)
          .update(current.copyWith(themeMode: mode));
      state = AsyncValue.data(saved);
    } on Object catch (error, stack) {
      state = AsyncValue.data(current);
      state = AsyncValue.error(error, stack);
    }
  }

  Future<void> uploadAvatar({
    required Uint8List bytes,
    required String fileName,
  }) async {
    state = const AsyncValue<Profile>.loading();
    state = await AsyncValue.guard(
      () => ref.read(profileRepositoryProvider).uploadAvatar(
            bytes: bytes,
            fileName: fileName,
          ),
    );
  }

  Future<void> removeAvatar() async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = const AsyncValue<Profile>.loading();
    state = await AsyncValue.guard(
      () => ref.read(profileRepositoryProvider).removeAvatar(current),
    );
  }

  Future<void> refresh() async {
    state = const AsyncValue<Profile>.loading();
    state = await AsyncValue.guard(
      () => ref.read(profileRepositoryProvider).fetch(),
    );
  }
}

final profileControllerProvider =
    AsyncNotifierProvider<ProfileController, Profile>(ProfileController.new);

/// The user's display currency.
///
/// Every `Money` in the UI is built with this, so a currency change is reflected
/// consistently instead of some screens defaulting to LKR.
final currencyProvider = Provider<String>((ref) {
  return ref.watch(profileControllerProvider).maybeWhen(
        data: (profile) => profile.defaultCurrency,
        orElse: () => 'LKR',
      );
});

/// The Flutter theme mode, derived from the stored preference.
final themeModeProvider = Provider<ThemeMode>((ref) {
  final mode = ref.watch(profileControllerProvider).maybeWhen(
        data: (profile) => profile.themeMode,
        orElse: () => AppThemeMode.system,
      );
  return switch (mode) {
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
    AppThemeMode.system => ThemeMode.system,
  };
});

/// Notification and security preferences.
class SettingsController extends AsyncNotifier<UserSettings> {
  @override
  Future<UserSettings> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) throw StateError('No signed-in user');
    return ref.watch(profileRepositoryProvider).fetchSettings();
  }

  /// Toggles one preference.
  ///
  /// Optimistic, because a switch that lags behind the finger feels broken; the
  /// previous value is restored if the save fails.
  Future<void> mutate(UserSettings Function(UserSettings) change) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final next = change(current);
    state = AsyncValue.data(next);

    try {
      final saved =
          await ref.read(profileRepositoryProvider).updateSettings(next);
      state = AsyncValue.data(saved);
    } on Object catch (error, stack) {
      state = AsyncValue.data(current);
      state = AsyncValue.error(error, stack);
    }
  }

  Future<void> setNotification(NotificationKind kind, bool enabled) =>
      mutate((s) => switch (kind) {
            NotificationKind.budgetWarning =>
              s.copyWith(notifyBudgetWarning: enabled),
            NotificationKind.budgetExceeded =>
              s.copyWith(notifyBudgetExceeded: enabled),
            NotificationKind.billDue => s.copyWith(notifyBillDue: enabled),
            NotificationKind.subscriptionRenewal =>
              s.copyWith(notifySubscriptionRenewal: enabled),
            NotificationKind.recurringDue =>
              s.copyWith(notifyRecurringDue: enabled),
            NotificationKind.ocrCompleted =>
              s.copyWith(notifyOcrCompleted: enabled),
            NotificationKind.ocrFailed => s.copyWith(notifyOcrFailed: enabled),
            NotificationKind.goalReached => s,
            // Shares the bill-due flag: it is the same "upcoming payment"
            // reminder category, and no settings toggle exposes this kind on
            // its own (see the curated list in settings_pages.dart).
            NotificationKind.creditCardDue =>
              s.copyWith(notifyBillDue: enabled),
          });

  Future<void> setDefaultAccount(String? accountId) =>
      mutate((s) => s.copyWith(defaultAccountId: accountId));

  /// Stores the default *and* applies it to this session, so the switch does
  /// something visible rather than only affecting the next launch.
  ///
  /// Hiding is immediate. Revealing goes through [PrivacyModeController.reveal]
  /// so it still honours [UserSettings.requireBiometricToReveal] — otherwise
  /// this switch would be a way around the very check it sits next to.
  Future<BiometricOutcome> setHideAmounts(bool hide) async {
    await mutate((s) => s.copyWith(hideAmountsOnDashboard: hide));

    final privacy = ref.read(privacyModeControllerProvider.notifier);
    if (hide) {
      privacy.hide();
      return BiometricOutcome.success;
    }
    return privacy.reveal();
  }

  Future<void> setRequireBiometricToReveal(bool required) =>
      mutate((s) => s.copyWith(requireBiometricToReveal: required));

  Future<void> setAutoHideOnBackground(bool enabled) =>
      mutate((s) => s.copyWith(autoHideOnBackground: enabled));

  Future<void> setRevealTimeout(int seconds) =>
      mutate((s) => s.copyWith(revealTimeoutSeconds: seconds));

  Future<void> setAppLockTimeout(int seconds) =>
      mutate((s) => s.copyWith(appLockTimeoutSeconds: seconds));

  /// Turns the app lock on or off.
  ///
  /// Switching it *on* verifies first. A lock you can enable without passing it
  /// once is a lock you may have just set on someone else's behalf, or with a
  /// sensor that does not work — either way the next launch would strand the
  /// owner outside their own records, with no password path back in.
  Future<BiometricOutcome> setBiometricLock(bool enabled) async {
    if (!enabled) {
      await mutate((s) => s.copyWith(biometricLockEnabled: false));
      return BiometricOutcome.success;
    }

    final capability = await ref.read(biometricServiceProvider).capability();
    if (!capability.canAuthenticate) return BiometricOutcome.notEnrolled;

    final outcome = await ref.read(biometricServiceProvider).authenticate(
          reason: 'Verify to turn on app lock',
        );
    if (!outcome.isSuccess) return outcome;

    await mutate((s) => s.copyWith(biometricLockEnabled: true));
    return BiometricOutcome.success;
  }
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, UserSettings>(
  SettingsController.new,
);

/// Whether financial figures are hidden right now.
///
/// Every screen and every [MoneyText] reads this one provider, so the eye on
/// the dashboard covers the whole app rather than one screen's figures.
///
/// It delegates to [privacyModeControllerProvider] — session state seeded from
/// [UserSettings.hideAmountsOnDashboard] — rather than reading the stored field
/// directly, so toggling the eye does not cost a Firestore write. Kept at this
/// name and in this file because fifteen screens already import it from here.
final hideAmountsProvider = Provider<bool>((ref) {
  return ref.watch(privacyModeControllerProvider);
});

/// The avatar's bytes, refreshed when the profile changes.
///
/// Bytes rather than a URL: the bucket is private and a Firebase download URL
/// would be a permanent, shareable token. Avatars are compressed to at most 400 KB
/// on upload, so holding one in memory is cheap.
final avatarBytesProvider = FutureProvider<Uint8List?>((ref) async {
  final profile = ref.watch(profileControllerProvider).valueOrNull;
  if (profile?.profileImageUrl == null) return null;
  return ref
      .watch(profileRepositoryProvider)
      .avatarBytes(profile!.profileImageUrl);
});
