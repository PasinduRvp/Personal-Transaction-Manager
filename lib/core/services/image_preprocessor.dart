import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:logging/logging.dart';

final _log = Logger('ImagePreprocessor');

/// The output of preprocessing: bytes to send to OCR plus what was done.
class PreprocessedImage {
  const PreprocessedImage({
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.appliedSteps,
    required this.originalBytes,
  });

  final Uint8List bytes;
  final String mimeType;
  final int width;
  final int height;
  final List<String> appliedSteps;

  /// Size of the file the user actually chose, for the "original preserved"
  /// guarantee and for the upload record.
  final int originalBytes;

  double get compressionRatio =>
      originalBytes == 0 ? 1 : bytes.length / originalBytes;
}

/// Prepares a photographed receipt for OCR.
///
/// The original file is uploaded to storage untouched — this operates on a copy
/// in memory that is sent to the OCR provider. Cleaning up the copy improves
/// recognition on phone photos (which are often over-large, slightly rotated
/// and unevenly lit) without ever rewriting the user's evidence.
class ImagePreprocessor {
  const ImagePreprocessor._();

  /// Long edge cap. Text recognition gains nothing above roughly this size,
  /// while upload time and provider cost both scale with pixels.
  static const int maxDimension = 2200;

  /// Below this, upscaling is pointless and would only blur the text.
  static const int minUsefulDimension = 600;

  static const int jpegQuality = 88;

  /// Returns the bytes to send for OCR. On any failure the original bytes are
  /// returned unchanged: a preprocessing bug must never block an import.
  static Future<PreprocessedImage> prepare(Uint8List original) async {
    final steps = <String>[];
    try {
      final decoded = img.decodeImage(original);
      if (decoded == null) {
        _log.info('Could not decode image; sending original bytes');
        return PreprocessedImage(
          bytes: original,
          mimeType: 'image/jpeg',
          width: 0,
          height: 0,
          appliedSteps: const ['none'],
          originalBytes: original.length,
        );
      }

      // EXIF orientation: phone cameras record rotation in metadata rather
      // than rotating pixels, and most OCR providers ignore the tag.
      var working = img.bakeOrientation(decoded);
      if (working.width != decoded.width || working.height != decoded.height) {
        steps.add('orientation');
      }

      final longEdge =
          working.width > working.height ? working.width : working.height;
      if (longEdge > maxDimension) {
        working = img.copyResize(
          working,
          width: working.width >= working.height ? maxDimension : null,
          height: working.height > working.width ? maxDimension : null,
          interpolation: img.Interpolation.cubic,
        );
        steps.add('resize');
      }

      // A mild contrast lift helps faint thermal-printer receipts. Kept gentle
      // on purpose: aggressive thresholding destroys thin digits, and a wrong
      // digit in an amount is worse than a slightly grey one.
      working = img.adjustColor(working, contrast: 1.12, saturation: 0.85);
      steps.add('contrast');

      final encoded = Uint8List.fromList(
        img.encodeJpg(working, quality: jpegQuality),
      );

      // Compression that made the file larger is not compression.
      final useProcessed = encoded.length < original.length || steps.length > 1;

      return PreprocessedImage(
        bytes: useProcessed ? encoded : original,
        mimeType: 'image/jpeg',
        width: working.width,
        height: working.height,
        appliedSteps: useProcessed ? steps : const ['none'],
        originalBytes: original.length,
      );
    } on Object catch (error, stack) {
      _log.warning('Preprocessing failed; falling back to original', error, stack);
      return PreprocessedImage(
        bytes: original,
        mimeType: 'image/jpeg',
        width: 0,
        height: 0,
        appliedSteps: const ['none'],
        originalBytes: original.length,
      );
    }
  }

  /// Compresses an image chosen as a receipt attachment (not for OCR), so
  /// storage stays reasonable. Returns the original when it is already small.
  static Future<Uint8List> compressForStorage(
    Uint8List original, {
    int maxBytes = 1200 * 1024,
  }) async {
    if (original.length <= maxBytes) return original;
    try {
      final decoded = img.decodeImage(original);
      if (decoded == null) return original;
      var working = img.bakeOrientation(decoded);
      final longEdge =
          working.width > working.height ? working.width : working.height;
      if (longEdge > maxDimension) {
        working = img.copyResize(
          working,
          width: working.width >= working.height ? maxDimension : null,
          height: working.height > working.width ? maxDimension : null,
          interpolation: img.Interpolation.cubic,
        );
      }
      for (final quality in [85, 75, 65]) {
        final encoded = Uint8List.fromList(img.encodeJpg(working, quality: quality));
        if (encoded.length <= maxBytes) return encoded;
      }
      return Uint8List.fromList(img.encodeJpg(working, quality: 60));
    } on Object catch (error) {
      _log.fine('Storage compression failed; using original', error);
      return original;
    }
  }

  /// Generates a small preview for list thumbnails.
  static Future<Uint8List?> thumbnail(Uint8List original, {int size = 320}) async {
    try {
      final decoded = img.decodeImage(original);
      if (decoded == null) return null;
      final baked = img.bakeOrientation(decoded);
      final resized = img.copyResize(
        baked,
        width: baked.width >= baked.height ? size : null,
        height: baked.height > baked.width ? size : null,
      );
      return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
    } on Object catch (_) {
      return null;
    }
  }
}
