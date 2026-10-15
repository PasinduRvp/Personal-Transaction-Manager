import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/errors/app_exception.dart';
import '../../core/errors/error_mapper.dart';
import 'repository_providers.dart';

final _log = Logger('AuthController');

/// Where the user is in the authentication flow.
///
/// A single enum rather than a set of booleans, so the router has exactly one
/// thing to switch on and cannot reach a contradictory state such as
/// "authenticated but also recovering a password".
enum AuthStatus {
  /// Still restoring a stored session.
  unknown,
  unauthenticated,

  /// Signed in, but the email address has not been confirmed yet.
  awaitingVerification,
  authenticated,
}

class AuthState {
  const AuthState({required this.status, this.user, this.errorMessage});

  final AuthStatus status;
  final fb.User? user;
  final String? errorMessage;

  bool get isSignedIn =>
      status == AuthStatus.authenticated ||
      status == AuthStatus.awaitingVerification;

  /// Only a verified session may reach the financial screens.
  bool get canAccessApp => status == AuthStatus.authenticated;

  String? get email => user?.email;
}

/// The single source of truth for authentication.
///
/// Driven by `authStateChanges` rather than by whatever the last screen did, so a
/// revoked token or a sign-out elsewhere is reflected everywhere at once —
/// including in the router's redirect.
///
/// There is no password-recovery state. Firebase completes a reset on its own
/// hosted page, so the app never holds a session whose only permitted action is
/// choosing a password; the user follows the emailed link, sets the password in
/// the browser and then signs in normally.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    final repository = ref.watch(authRepositoryProvider);

    final subscription = repository.onAuthStateChange.listen(
      (user) {
        state = _stateFor(user);
        // Recurring transactions, bill statuses and subscription renewals have no
        // scheduler behind them on the free plan, so they are swept when a verified
        // user arrives. It rate-limits itself to once every six hours and never
        // throws, so this cannot delay or break sign-in.
        if (user != null && user.emailVerified) {
          unawaited(ref.read(maintenanceRunnerProvider).runIfDue());
        }
      },
      onError: (Object error) {
        state = AuthState(
          status: AuthStatus.unauthenticated,
          errorMessage: ErrorMapper.map(error).message,
        );
      },
    );
    ref.onDispose(subscription.cancel);

    return _stateFor(repository.currentUser);
  }

  static AuthState _stateFor(fb.User? user) {
    if (user == null) {
      return const AuthState(status: AuthStatus.unauthenticated);
    }
    if (!user.emailVerified) {
      return AuthState(status: AuthStatus.awaitingVerification, user: user);
    }
    return AuthState(status: AuthStatus.authenticated, user: user);
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) =>
      ref.read(authRepositoryProvider).signIn(email: email, password: password);

  Future<void> signUp({
    required String email,
    required String fullName,
    required String password,
    String? defaultCurrency,
  }) =>
      ref.read(authRepositoryProvider).signUp(
            email: email,
            fullName: fullName,
            password: password,
            defaultCurrency: defaultCurrency,
          );

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> sendPasswordReset(String email) =>
      ref.read(authRepositoryProvider).sendPasswordReset(email);

  /// Changes the password of the signed-in user.
  ///
  /// The current password is required and checked by reauthenticating: Firebase
  /// refuses `updatePassword` on a session that has not signed in recently, and
  /// asking for the existing password is both what satisfies that and what stops
  /// someone with a borrowed unlocked phone from taking the account over.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final repository = ref.read(authRepositoryProvider);

    final verified = await repository.verifyPassword(currentPassword);
    if (!verified) {
      throw const AuthenticationException(
        'That current password is not correct.',
      );
    }

    await repository.updatePassword(newPassword);
  }

  Future<void> resendVerification(String email) =>
      ref.read(authRepositoryProvider).resendConfirmation(email);

  /// Re-checks verification after the user says they have clicked the link.
  Future<bool> refreshVerification() async {
    final repository = ref.read(authRepositoryProvider);
    final verified = await repository.refreshVerificationStatus();
    if (!verified) return false;

    // Seed again on the way through. Sign-up already tries, but it runs before the
    // address is confirmed and can be refused — and a user arriving at the dashboard
    // with no profile sees nothing but an error, which is the worst possible first
    // screen. This is the moment the account is known to be complete, so it is the
    // right place to make sure its scaffolding exists.
    //
    // Idempotent, so an account that seeded correctly at sign-up pays one cached
    // read for this and nothing more.
    try {
      await ref.read(accountSeederProvider).ensureSeeded();
    } on Object catch (error, stack) {
      _log.warning('Could not seed after verification', error, stack);
    }

    state = AuthState(
      status: AuthStatus.authenticated,
      user: repository.currentUser,
    );
    return true;
  }

  Future<bool> verifyPassword(String password) =>
      ref.read(authRepositoryProvider).verifyPassword(password);
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// The signed-in user's id, or null.
///
/// Providers that load user data watch this, so they rebuild — and drop the
/// previous user's data — the moment the signed-in user changes.
final currentUserIdProvider = Provider<String?>(
  (ref) => ref.watch(authControllerProvider).user?.uid,
);

final isAuthenticatedProvider = Provider<bool>(
  (ref) => ref.watch(authControllerProvider).canAccessApp,
);

/// Guards a provider that must not run while signed out.
String requireUserId(Ref ref) {
  final id = ref.watch(currentUserIdProvider);
  if (id == null) {
    throw const AuthenticationException('Please sign in again.');
  }
  return id;
}
