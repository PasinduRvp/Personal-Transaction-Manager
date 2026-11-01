import 'package:finora/shared/providers/profile_providers.dart';
import 'package:finora/shared/providers/security_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The privacy toggle's session behaviour.
///
/// No Firebase is initialised here, which is the point: the controller is
/// built so that rendering a figure never depends on a signed-in user. If
/// these start failing with an authentication error, something has added a
/// dependency that would also crash a widget test rendering a `MoneyText`.
void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  PrivacyModeController controller() =>
      container.read(privacyModeControllerProvider.notifier);

  bool hidden() => container.read(privacyModeControllerProvider);

  group('Defaults', () {
    test('amounts start visible', () {
      expect(hidden(), isFalse);
      expect(container.read(hideAmountsProvider), isFalse);
    });

    test('hideAmountsProvider follows the controller', () {
      controller().hide();
      expect(container.read(hideAmountsProvider), isTrue);
    });
  });

  group('Stored default', () {
    test('is applied the first time settings arrive', () {
      controller().applyStoredDefault(true);
      expect(hidden(), isTrue);
    });

    test('is applied only once, so it cannot undo a later choice', () {
      // Settings are saved whenever any unrelated toggle changes. Re-applying
      // the stored default each time would re-hide amounts the user had just
      // chosen to reveal.
      controller().applyStoredDefault(true);
      expect(hidden(), isTrue);

      controller().hide();
      container.read(privacyModeControllerProvider.notifier).state = false;

      controller().applyStoredDefault(true);
      expect(hidden(), isFalse);
    });
  });

  group('Hiding', () {
    test('hide always works and needs no verification', () {
      controller().hide();
      expect(hidden(), isTrue);
    });

    test('hiding twice is harmless', () {
      controller()
        ..hide()
        ..hide();
      expect(hidden(), isTrue);
    });

    test('backgrounding hides when no settings have loaded', () {
      // Fail closed. With nothing loaded the app cannot know the user opted
      // out, and covering the figures is the safe direction to guess in.
      controller().hideForBackground();
      expect(hidden(), isTrue);
    });
  });

  group('Revealing', () {
    test('reveals when no biometric check is required', () async {
      controller().hide();
      expect(hidden(), isTrue);

      final outcome = await controller().reveal();

      expect(outcome.isSuccess, isTrue);
      expect(hidden(), isFalse);
    });

    test('revealing something already visible is a no-op success', () async {
      final outcome = await controller().reveal();

      expect(outcome.isSuccess, isTrue);
      expect(hidden(), isFalse);
    });

    test('toggle hides when visible and reveals when hidden', () async {
      await controller().toggle();
      expect(hidden(), isTrue);

      await controller().toggle();
      expect(hidden(), isFalse);
    });
  });

  group('App lock', () {
    AppLockController lock() =>
        container.read(appLockControllerProvider.notifier);

    AppLockStatus status() => container.read(appLockControllerProvider);

    test('starts unlocked', () {
      expect(status(), AppLockStatus.unlocked);
      expect(status().isLocked, isFalse);
    });

    test('locking is idempotent', () {
      lock()
        ..lock()
        ..lock();
      expect(status(), AppLockStatus.locked);
    });

    test('a resume with no recorded departure does not lock', () {
      // Nothing backgrounded the app, so there is nothing to re-lock after.
      lock().onResumed(lockEnabled: true, timeoutSeconds: 0);
      expect(status(), AppLockStatus.unlocked);
    });

    test('a resume inside the grace period does not lock', () {
      lock()
        ..markLeftForeground()
        ..onResumed(lockEnabled: true, timeoutSeconds: 300);

      expect(status(), AppLockStatus.unlocked);
    });

    test('a resume locks immediately when the timeout is zero', () {
      lock()
        ..markLeftForeground()
        ..onResumed(lockEnabled: true, timeoutSeconds: 0);

      expect(status(), AppLockStatus.locked);
    });

    test('the lock stays off when the setting is off', () {
      lock()
        ..markLeftForeground()
        ..onResumed(lockEnabled: false, timeoutSeconds: 0);

      expect(status(), AppLockStatus.unlocked);
    });

    test('the recorded departure is consumed, not reused', () {
      // Otherwise a single backgrounding would lock the app on every
      // subsequent resume, including ones the user never left.
      lock()
        ..markLeftForeground()
        ..onResumed(lockEnabled: true, timeoutSeconds: 300);
      expect(status(), AppLockStatus.unlocked);

      lock().onResumed(lockEnabled: true, timeoutSeconds: 0);
      expect(status(), AppLockStatus.unlocked);
    });

    test('signing out clears the lock rather than leaving it over login', () {
      lock()
        ..lock()
        ..unlockWithoutPrompt();

      expect(status(), AppLockStatus.unlocked);
    });
  });
}
