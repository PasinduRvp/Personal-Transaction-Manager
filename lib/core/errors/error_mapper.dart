import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:logging/logging.dart';

import 'app_exception.dart';

final _log = Logger('ErrorMapper');

/// Translates every low-level failure into an [AppException] whose `message` is
/// safe to display.
///
/// This is the only place in the app that knows what a Firebase error code looks
/// like. Nothing above the repository layer sees a `FirebaseException`, so a
/// screen cannot accidentally render `permission-denied` or a document path.
class ErrorMapper {
  const ErrorMapper._();

  static AppException map(Object error, [StackTrace? stackTrace]) {
    if (error is AppException) return error;

    _log.warning('Mapping ${error.runtimeType}', error, stackTrace);

    // --- Connectivity -----------------------------------------------------
    if (error is SocketException || error is HttpException) {
      return NetworkException(debugDetail: error.toString(), cause: error);
    }
    if (error is TimeoutException) {
      return const NetworkException(
        message: 'The request took too long. Please try again.',
      );
    }

    // --- Auth --------------------------------------------------------------
    if (error is FirebaseAuthException) {
      return AuthenticationException(
        _authMessage(error),
        debugDetail: '${error.code}: ${error.message}',
        cause: error,
      );
    }

    // --- Firestore ---------------------------------------------------------
    if (error is FirebaseException && error.plugin == 'cloud_firestore') {
      return _mapFirestore(error);
    }

    // --- Storage -----------------------------------------------------------
    if (error is FirebaseException && error.plugin == 'firebase_storage') {
      return _mapStorage(error);
    }

    if (error is FirebaseException) {
      return UnexpectedException(
        debugDetail: '${error.plugin}/${error.code}: ${error.message}',
        cause: error,
      );
    }

    if (error is FormatException) {
      return UnexpectedException(
        message: 'We received an unexpected response. Please try again.',
        debugDetail: error.toString(),
        cause: error,
      );
    }

    return UnexpectedException(debugDetail: error.toString(), cause: error);
  }

  static String _authMessage(FirebaseAuthException error) {
    switch (error.code) {
      // Firebase returns this for a wrong password, an unknown address and a
      // malformed one alike when email enumeration protection is on. Saying
      // which would turn the sign-in form into an account-existence oracle, so
      // the message stays deliberately joint.
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-email':
        return 'That email or password is incorrect.';

      case 'email-already-in-use':
        return 'An account already exists for that email address.';
      case 'weak-password':
        return 'Please choose a password with at least 8 characters.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'requires-recent-login':
        return 'Please sign in again to make this change.';
      case 'expired-action-code':
      case 'invalid-action-code':
        return 'That link has expired. Please request a new one.';
      case 'network-request-failed':
        return 'No internet connection. Check your network and try again.';
      case 'operation-not-allowed':
        // A configuration problem, not something a user can fix, so it does not
        // pretend to be actionable.
        return 'Sign-in is unavailable right now. Please try again later.';
      default:
        return 'We could not complete that request. Please try again.';
    }
  }

  static AppException _mapFirestore(FirebaseException error) {
    final detail = '${error.code}: ${error.message}';

    switch (error.code) {
      // The security rules refused it. Either the document is not the caller's,
      // or the write touched a field only a Cloud Function may change.
      case 'permission-denied':
        return PermissionException(debugDetail: detail, cause: error);

      case 'unauthenticated':
        return const AuthenticationException(
          'Your session has expired. Please sign in again.',
        );

      case 'not-found':
        return NotFoundException(debugDetail: detail, cause: error);

      case 'already-exists':
        return DatabaseException(
          message: 'That item already exists.',
          debugDetail: detail,
          cause: error,
        );

      case 'unavailable':
      case 'deadline-exceeded':
        return NetworkException(
          message: 'We could not reach the server. Check your connection and '
              'try again.',
          debugDetail: detail,
          cause: error,
        );

      // Composite index missing or still building. The console URL is in the log.
      case 'failed-precondition':
        _log.severe('Firestore precondition failed (missing index?): $detail');
        final building = detail.contains('currently building');
        return DatabaseException(
          message: building
              ? 'The database is still setting up indexes. Wait a few minutes, '
                  'then tap Try again.'
              : 'We could not load your data. If this persists, check that '
                  'Firestore indexes are deployed.',
          debugDetail: detail,
          cause: error,
        );

      case 'resource-exhausted':
        return DatabaseException(
          message: 'The service is busy. Please try again in a moment.',
          debugDetail: detail,
          cause: error,
        );

      case 'aborted':
        return DatabaseException(
          message: 'Someone else changed that at the same time. Please try '
              'again.',
          debugDetail: detail,
          cause: error,
        );

      case 'cancelled':
        return const NetworkException(
          message: 'That request was interrupted. Please try again.',
        );

      default:
        return DatabaseException(debugDetail: detail, cause: error);
    }
  }

  static AppException _mapStorage(FirebaseException error) {
    final detail = '${error.code}: ${error.message}';

    switch (error.code) {
      case 'object-not-found':
        return const NotFoundException(
          message: 'That file is no longer available.',
        );
      case 'unauthorized':
      case 'unauthenticated':
        return const PermissionException(
          message: 'You do not have access to that file.',
        );
      case 'quota-exceeded':
        return const StorageException(
          message: 'Storage is full. Delete some documents and try again.',
        );
      case 'retry-limit-exceeded':
      case 'canceled':
        return const StorageException(
          message: 'The upload did not finish. Please try again.',
        );
      default:
        return StorageException(debugDetail: detail, cause: error);
    }
  }
}
