class AppConstants {
  const AppConstants._();

  static const String appName = 'Finora';
  static const String appTagline = 'Personal Transaction Manager';

  /// Transactions fetched per page in infinite-scroll lists.
  static const int transactionPageSize = 20;

  // Storage folder names live in `Paths` (core/services/firebase_service.dart),
  // alongside the Firestore collection names, so an object path and the document
  // that references it are defined in one place.

  static const List<String> allowedImageExtensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
  ];
  static const List<String> allowedDocumentExtensions = ['pdf'];

  static List<String> get allowedExtensions =>
      [...allowedImageExtensions, ...allowedDocumentExtensions];

  /// Longest we wait for an OCR job before telling the user it timed out.
  static const Duration ocrPollTimeout = Duration(minutes: 3);
  static const Duration ocrPollInterval = Duration(seconds: 2);

  /// A field below this confidence is flagged for manual verification.
  static const double lowConfidenceThreshold = 0.80;

  /// Window used when looking for a possible duplicate transaction.
  static const int duplicateDateToleranceDays = 3;
}
