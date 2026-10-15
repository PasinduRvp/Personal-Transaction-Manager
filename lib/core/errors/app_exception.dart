/// Finora's exception hierarchy.
///
/// Every layer below the UI throws one of these. Each carries a [message] that
/// is safe to show to a user and an optional [debugDetail] that is only ever
/// logged. Stack traces, SQL text, storage paths and provider responses stay
/// in [debugDetail] and never reach the screen.
sealed class AppException implements Exception {
  const AppException(this.message, {this.debugDetail, this.cause});

  /// User-facing, plain language, no technical terms.
  final String message;

  /// Developer-facing detail. Logged, never displayed.
  final String? debugDetail;

  final Object? cause;

  @override
  String toString() => '$runtimeType: $message'
      '${debugDetail == null ? '' : ' (detail: $debugDetail)'}';
}

class NetworkException extends AppException {
  const NetworkException({
    String message =
        'No internet connection. Check your network and try again.',
    super.debugDetail,
    super.cause,
  }) : super(message);
}

class AuthenticationException extends AppException {
  const AuthenticationException(super.message, {super.debugDetail, super.cause});

  /// True when the user simply needs to sign in again.
  bool get requiresReauthentication => true;
}

class DatabaseException extends AppException {
  const DatabaseException({
    String message = 'We could not save your changes. Please try again.',
    super.debugDetail,
    super.cause,
  }) : super(message);
}

class StorageException extends AppException {
  const StorageException({
    String message = 'We could not upload your file. Please try again.',
    super.debugDetail,
    super.cause,
  }) : super(message);
}

class OcrException extends AppException {
  const OcrException(
    super.message, {
    this.kind = OcrFailureKind.unknown,
    super.debugDetail,
    super.cause,
  });

  final OcrFailureKind kind;

  /// Actionable suggestions shown as a bullet list beneath the message.
  List<String> get suggestions => switch (kind) {
        OcrFailureKind.unreadable => const [
            'Use a clearer, well-lit photo',
            'Hold the camera straight above the document',
            'Make sure the whole receipt is inside the frame',
          ],
        OcrFailureKind.noTextFound => const [
            'Check that the document contains printed text',
            'Try a higher-resolution scan',
          ],
        OcrFailureKind.unsupportedFile => const [
            'Upload a JPG, PNG, WEBP or PDF file',
          ],
        OcrFailureKind.corruptFile => const [
            'Open the file on your device to confirm it works',
            'Try exporting or scanning the document again',
          ],
        OcrFailureKind.tooManyPages => const [
            'Split the document into smaller parts',
            'Upload only the pages with transactions',
          ],
        OcrFailureKind.timeout => const [
            'Try again in a moment',
            'Large documents can take longer to read',
          ],
        OcrFailureKind.providerUnavailable => const [
            'Document reading is temporarily unavailable',
            'You can still add this transaction manually',
          ],
        OcrFailureKind.unknown => const [
            'Try uploading the document again',
            'You can always add the transaction manually',
          ],
      };
}

enum OcrFailureKind {
  unreadable,
  noTextFound,
  unsupportedFile,
  corruptFile,
  tooManyPages,
  timeout,
  providerUnavailable,
  unknown;

  static OcrFailureKind fromWire(String? raw) {
    switch (raw?.toUpperCase()) {
      case 'UNREADABLE':
      case 'LOW_QUALITY':
        return unreadable;
      case 'NO_TEXT_FOUND':
      case 'EMPTY_DOCUMENT':
        return noTextFound;
      case 'UNSUPPORTED_FILE':
        return unsupportedFile;
      case 'CORRUPT_FILE':
        return corruptFile;
      case 'TOO_MANY_PAGES':
        return tooManyPages;
      case 'TIMEOUT':
        return timeout;
      case 'PROVIDER_UNAVAILABLE':
        return providerUnavailable;
      default:
        return unknown;
    }
  }
}

class ValidationException extends AppException {
  const ValidationException(
    super.message, {
    this.fieldErrors = const {},
    super.debugDetail,
    super.cause,
  });

  /// Field name to error message, for inline form display.
  final Map<String, String> fieldErrors;
}

class FileException extends AppException {
  const FileException(super.message, {super.debugDetail, super.cause});
}

class NotFoundException extends AppException {
  const NotFoundException({
    String message = 'We could not find that item. It may have been deleted.',
    super.debugDetail,
    super.cause,
  }) : super(message);
}

class PermissionException extends AppException {
  const PermissionException({
    String message = 'You do not have permission to do that.',
    super.debugDetail,
    super.cause,
  }) : super(message);
}

class UnexpectedException extends AppException {
  const UnexpectedException({
    String message = 'Something went wrong. Please try again.',
    super.debugDetail,
    super.cause,
  }) : super(message);
}
