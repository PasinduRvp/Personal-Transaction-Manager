import 'package:firebase_auth/firebase_auth.dart';
import 'package:logging/logging.dart';

import '../../core/errors/app_exception.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/services/cache_service.dart';
import '../../core/services/firebase_service.dart';
import '../../core/services/document_store.dart';
import 'account_seeder.dart';
import 'relation_loader.dart';

final _log = Logger('AuthRepository');

/// Wraps Firebase Auth.
///
/// The client never stores a password and never derives a user id from anything
/// but the current session. Sign-out clears the device's cached financial data as
/// well as the session, so a shared phone does not leak the previous user's
/// balances — Firestore's offline cache is persistent, which makes that step
/// necessary rather than merely tidy.
class AuthRepository {
  AuthRepository({
    FirebaseAuth? auth,
    CacheService? cache,
    DocumentStore? store,
    AccountSeeder? seeder,
  })  : _auth = auth ?? FirebaseService.auth,
        _cache = cache,
        _store = store,
        _seeder = seeder ?? AccountSeeder();

  final FirebaseAuth _auth;
  final CacheService? _cache;
  final DocumentStore? _store;
  final AccountSeeder _seeder;

  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => _auth.currentUser != null;

  /// Emits on sign-in, sign-out and token refresh.
  ///
  /// `authStateChanges` rather than `userChanges`: the latter also fires on every
  /// profile mutation, which would rebuild the router's redirect for a display
  /// name change.
  Stream<User?> get onAuthStateChange => _auth.authStateChanges();

  /// Creates the account and sends the verification email.
  ///
  /// The display name is set on the Firebase user so the `onUserCreate` function
  /// can seed the profile document from it. Nothing else about the user is written
  /// here: the profile, the settings and the default categories are the function's
  /// job, because two devices signing up the same account would otherwise race to
  /// create them.
  Future<void> signUp({
    required String email,
    required String fullName,
    required String password,
    String? defaultCurrency,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = credential.user;
      if (user == null) {
        throw const AuthenticationException(
          'We could not create your account. Please try again.',
        );
      }

      await user.updateDisplayName(fullName.trim());
      await _seed(fullName: fullName, defaultCurrency: defaultCurrency);
      await user.sendEmailVerification();

      _log.info('Sign-up submitted');
    } on Object catch (error, stack) {
      throw ErrorMapper.map(error, stack);
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      // Also on sign-in, not only on sign-up. A sign-up whose seeding never ran —
      // the app was killed partway, or the device was offline — would otherwise
      // leave a user with no profile and no categories, and no way to get them.
      await _seed();
    } on Object catch (error, stack) {
      throw ErrorMapper.map(error, stack);
    }
  }

  /// Creates the profile, settings and default categories if they are missing.
  ///
  /// Idempotent, and safe to call on every sign-in: the seeder checks a marker
  /// inside a Firestore transaction, so two devices racing cannot both write a set
  /// of categories.
  ///
  /// Failures are swallowed deliberately. The account exists and the user is signed
  /// in; blocking them on a write that will be retried on their next sign-in would
  /// be the wrong trade, and the screens that need the profile report its absence
  /// themselves.
  Future<void> _seed({String? fullName, String? defaultCurrency}) async {
    try {
      await _seeder.ensureSeeded(
        fullName: fullName,
        defaultCurrency: defaultCurrency,
      );
    } on Object catch (error, stack) {
      _log.warning('Could not seed the account', error, stack);
    }
  }

  Future<void> signOut() async {
    final userId = _auth.currentUser?.uid;

    try {
      // Firestore's local cache survives sign-out and is readable by whoever uses
      // the device next, so it is cleared before the session goes. The network has
      // to be disabled first: `clearPersistence` refuses to run while there is an
      // active connection.
      await FirebaseService.firestore.terminate();
      await FirebaseService.firestore.clearPersistence();
      await FirebaseService.firestore.enableNetwork();
    } on Object catch (error, stack) {
      _log.warning('Could not clear the local Firestore cache', error, stack);
    }

    try {
      await _auth.signOut();
    } on Object catch (error, stack) {
      // Even if the call fails, the local credentials are gone; log it but do not
      // leave the user stuck on a signed-in screen.
      _log.warning('Sign-out returned an error', error, stack);
    } finally {
      // Documents are stored per user on this device, so the previous user's
      // receipts must not be readable by whoever signs in next.
      if (userId != null) await _store?.deleteAllFor(userId);
      RelationLoader.invalidate();
      if (userId != null) {
        await _cache?.clearForUser(userId);
      } else {
        await _cache?.clearAll();
      }
    }
  }

  /// Sends a password recovery email.
  ///
  /// Always reports success, whatever the server says about the address. Telling
  /// a caller that an email is not registered would turn this into an
  /// account-existence oracle — and Firebase's email enumeration protection, which
  /// the setup guide turns on, makes the same guarantee on the server.
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      // Rate limiting is worth surfacing: the user needs to know to wait.
      if (error.code == 'too-many-requests') {
        throw ErrorMapper.map(error);
      }
      _log.info('Password reset request suppressed error: ${error.code}');
    } on Object catch (error, stack) {
      _log.warning('Password reset request failed', error, stack);
    }
  }

  /// Changes the password of the signed-in user.
  ///
  /// Firebase requires a recent sign-in for this, so [verifyPassword] is called
  /// first by the settings screen; a stale session surfaces as
  /// `requires-recent-login`, which the mapper turns into a request to sign in
  /// again.
  Future<void> updatePassword(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthenticationException(
        'Your session has expired. Please sign in again.',
      );
    }
    try {
      await user.updatePassword(newPassword);
    } on Object catch (error, stack) {
      throw ErrorMapper.map(error, stack);
    }
  }

  /// Completes a recovery flow started from an emailed link.
  ///
  /// Firebase handles the reset itself, on its own hosted page or through a
  /// dynamic link, so the app does not take a new password here. This re-reads the
  /// user so a password changed elsewhere invalidates the session promptly.
  Future<void> reloadUser() async {
    try {
      await _auth.currentUser?.reload();
    } on Object catch (error, stack) {
      _log.fine('Could not reload the user', error, stack);
    }
  }

  Future<void> resendConfirmation(String email) async {
    final user = _auth.currentUser;
    if (user == null) {
      // Firebase can only resend for the signed-in user, so an unauthenticated
      // caller is told what to do rather than given a silent no-op.
      throw const AuthenticationException(
        'Sign in first and we will send the verification email again.',
      );
    }
    try {
      await user.sendEmailVerification();
    } on Object catch (error, stack) {
      throw ErrorMapper.map(error, stack);
    }
  }

  /// True once the user has confirmed their email address.
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  /// Re-checks the user against the server, used after returning from an email
  /// link.
  ///
  /// `reload` is necessary: `emailVerified` comes from the cached ID token, which
  /// keeps saying false for up to an hour after the address is confirmed.
  Future<bool> refreshVerificationStatus() async {
    try {
      await _auth.currentUser?.reload();
      return _auth.currentUser?.emailVerified ?? false;
    } on Object catch (error, stack) {
      _log.fine('Could not refresh verification status', error, stack);
      return isEmailVerified;
    }
  }

  /// Confirms the user's password without disturbing the current session.
  ///
  /// Used to gate destructive actions such as account deletion. Reauthentication
  /// rather than a fresh sign-in: it checks the credential against the same user
  /// and, on success, satisfies Firebase's recent-login requirement for the
  /// operation that follows.
  Future<bool> verifyPassword(String password) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) return false;

    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
      return true;
    } on FirebaseAuthException catch (error) {
      // A wrong password is an answer, not a failure. Anything else — a network
      // problem, a disabled account — is reported rather than reported as "wrong
      // password", which would send the user looking for the wrong fix.
      if (error.code == 'invalid-credential' ||
          error.code == 'wrong-password' ||
          error.code == 'invalid-email' ||
          error.code == 'user-mismatch') {
        return false;
      }
      throw ErrorMapper.map(error);
    } on Object catch (error, stack) {
      throw ErrorMapper.map(error, stack);
    }
  }
}
