import 'package:finora/core/constants/enums.dart';
import 'package:finora/shared/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// Settings are the one model where a field that silently fails to persist is
/// invisible until a user reopens the app and finds their app lock switched
/// off. So each new flag is asserted through a full write-and-read cycle, not
/// just on the object in memory.
void main() {
  group('Security and privacy defaults', () {
    test('a brand new user is not locked out of anything', () {
      const settings = UserSettings(userId: 'u1');

      expect(settings.biometricLockEnabled, isFalse);
      expect(settings.requireBiometricToReveal, isFalse);
      expect(settings.hideAmountsOnDashboard, isFalse);
      expect(settings.appLockTimeoutSeconds, 0);
      expect(settings.revealTimeoutSeconds, 0);
    });

    test('hiding on background is on by default', () {
      // The one privacy default that starts on: it costs nothing when no
      // amounts are hidden, and it is what keeps balances out of the
      // app-switcher preview for everyone who does hide them.
      expect(const UserSettings(userId: 'u1').autoHideOnBackground, isTrue);
    });

    test('a settings document missing the new fields keeps working', () {
      // Every existing user's stored document predates these fields. Reading
      // one must not change behaviour they did not ask to change.
      final settings = UserSettings.fromJson({
        'user_id': 'u1',
        'notify_budget_warning': true,
      });

      expect(settings.biometricLockEnabled, isFalse);
      expect(settings.requireBiometricToReveal, isFalse);
      expect(settings.autoHideOnBackground, isTrue);
      expect(settings.appLockTimeoutSeconds, 0);
      expect(settings.revealTimeoutSeconds, 0);
    });
  });

  group('Round trip', () {
    test('every security field survives a write and a read', () {
      const original = UserSettings(
        userId: 'u1',
        biometricLockEnabled: true,
        appLockTimeoutSeconds: 60,
        hideAmountsOnDashboard: true,
        requireBiometricToReveal: true,
        autoHideOnBackground: false,
        revealTimeoutSeconds: 30,
      );

      final restored = UserSettings.fromJson({
        'user_id': 'u1',
        ...original.toUpdateJson(),
      });

      expect(restored.biometricLockEnabled, isTrue);
      expect(restored.appLockTimeoutSeconds, 60);
      expect(restored.hideAmountsOnDashboard, isTrue);
      expect(restored.requireBiometricToReveal, isTrue);
      expect(restored.autoHideOnBackground, isFalse);
      expect(restored.revealTimeoutSeconds, 30);
    });

    test('notification flags still round trip alongside them', () {
      const original = UserSettings(
        userId: 'u1',
        notifyBudgetWarning: false,
        notifyBudgetExceeded: true,
        notifyOcrFailed: false,
      );

      final restored = UserSettings.fromJson({
        'user_id': 'u1',
        ...original.toUpdateJson(),
      });

      expect(restored.isEnabled(NotificationKind.budgetWarning), isFalse);
      expect(restored.isEnabled(NotificationKind.budgetExceeded), isTrue);
      expect(restored.isEnabled(NotificationKind.ocrFailed), isFalse);
    });

    test('copyWith changes one field and leaves the rest alone', () {
      const original = UserSettings(
        userId: 'u1',
        biometricLockEnabled: true,
        revealTimeoutSeconds: 30,
      );

      final updated = original.copyWith(appLockTimeoutSeconds: 300);

      expect(updated.appLockTimeoutSeconds, 300);
      expect(updated.biometricLockEnabled, isTrue);
      expect(updated.revealTimeoutSeconds, 30);
    });
  });

  group('Alert routing', () {
    test('muting budget warnings does not mute exceedances', () {
      // Two separate flags on purpose: someone who does not want to be nagged
      // at 75% usually still wants to know when the budget is gone.
      const settings = UserSettings(
        userId: 'u1',
        notifyBudgetWarning: false,
        notifyBudgetExceeded: true,
      );

      expect(settings.isEnabled(BudgetAlertLevel.threeQuarters.kind), isFalse);
      expect(settings.isEnabled(BudgetAlertLevel.ninety.kind), isFalse);
      expect(settings.isEnabled(BudgetAlertLevel.spent.kind), isTrue);
      expect(settings.isEnabled(BudgetAlertLevel.overspent.kind), isTrue);
    });

    test('a credit card reminder follows the bill-due flag', () {
      const settings = UserSettings(userId: 'u1', notifyBillDue: false);

      expect(settings.isEnabled(NotificationKind.creditCardDue), isFalse);
    });
  });

  group('Privacy summary', () {
    test('reports whether anything is actually protecting the figures', () {
      expect(const UserSettings(userId: 'u1').hasPrivacyProtection, isFalse);
      expect(
        const UserSettings(userId: 'u1', biometricLockEnabled: true)
            .hasPrivacyProtection,
        isTrue,
      );
      expect(
        const UserSettings(userId: 'u1', hideAmountsOnDashboard: true)
            .hasPrivacyProtection,
        isTrue,
      );
    });
  });
}
