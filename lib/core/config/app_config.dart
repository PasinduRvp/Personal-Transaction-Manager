/// Centralised, compile-time configuration for Finora.
///
/// Nothing in this class may ever hold a provider secret. Under Firebase there is
/// no URL or key to supply at all: the project details come from
/// `google-services.json` on Android and from `firebase_options.dart`, both of
/// which are public identifiers rather than credentials — access is decided by
/// the security rules and the signed-in user's token, not by possession of them.
///
/// The OCR provider's API key lives in Secret Manager and is read only by the
/// Cloud Function. It is never compiled into the app, so a decompiled APK yields
/// nothing that can spend the project's quota.
///
/// What remains here are limits the UI enforces before an upload, kept
/// overridable with `--dart-define` so a build can be tightened without a code
/// change.
class AppConfig {
  const AppConfig._();

  /// Maximum upload size for a document, in megabytes.
  ///
  /// Mirrored by the storage rules, which are what actually enforce it — this
  /// value exists so the user is told before a large file is uploaded rather than
  /// after it is rejected.
  static const int maxUploadMb =
      int.fromEnvironment('MAX_UPLOAD_MB', defaultValue: 15);

  /// Maximum number of PDF pages accepted for a single import.
  static const int maxPdfPages =
      int.fromEnvironment('MAX_PDF_PAGES', defaultValue: 30);

  static int get maxUploadBytes => maxUploadMb * 1024 * 1024;

  /// Always true: there is nothing left for the operator to supply at build time.
  ///
  /// Kept so the startup path still has one place to ask "can this build run",
  /// which is where a future required setting would go.
  static bool get isConfigured => true;

  /// Human readable description of what is missing, for the startup screen.
  static String get configurationHint => '';
}
