import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../errors/app_exception.dart';

final _log = Logger('TextRecogniser');

/// One recognised page.
class RecognisedPage {
  const RecognisedPage({
    required this.pageNumber,
    required this.text,
    required this.confidence,
    required this.lines,
  });

  final int pageNumber;
  final String text;

  /// 0–1, or null when the recogniser does not report one.
  final double? confidence;

  /// Individual lines in reading order, used by the statement parser.
  final List<String> lines;
}

class RecognitionResult {
  const RecognitionResult({
    required this.provider,
    required this.pages,
    required this.confidence,
    required this.metadata,
  });

  final String provider;
  final List<RecognisedPage> pages;
  final double? confidence;
  final Map<String, dynamic> metadata;

  /// Every page's text, in order.
  String get fullText => pages.map((page) => page.text).join('\n');
}

/// What a recogniser must do.
///
/// The interface survives from the cloud implementation unchanged, which is the
/// point of having had one: the parser, the review workflow and the data layer all
/// sit above this and none of them knew the recogniser moved from a Google Cloud
/// API to the phone. Swapping back, or adding a cloud option for scanned PDFs,
/// means writing one class.
abstract class TextRecogniser {
  String get name;

  /// Whether this recogniser can read a PDF directly.
  bool get supportsPdf;

  Future<RecognitionResult> recognise({
    required Uint8List bytes,
    required String mimeType,
    required String fileName,
  });

  Future<void> dispose();
}

/// Google ML Kit, running on the device.
///
/// **No API key exists anywhere in this app.** The specification required that OCR
/// credentials never ship in the client, and the usual way to honour that is to put
/// the key on a server. Without a server the honest answer is not to have a key at
/// all: ML Kit downloads its model through Google Play Services and runs locally.
///
/// Three things follow, all of them improvements:
///
///   * **Receipts never leave the phone.** A bank statement is not uploaded
///     anywhere to be read, which is a stronger privacy position than the cloud
///     pipeline had.
///   * **It works offline**, which matters for an app that already stores its data
///     offline.
///   * **It costs nothing**, with no quota to exhaust and no bill to watch.
///
/// The limitation is real: ML Kit reads images, not PDFs. A text-layer PDF is
/// handled without any recogniser at all by [PdfTextExtractor]; a *scanned* PDF
/// cannot be read on-device, and the app says so rather than failing obscurely.
class MlKitTextRecogniser implements TextRecogniser {
  MlKitTextRecogniser();

  TextRecognizer? _recogniser;

  @override
  String get name => 'mlkit-on-device';

  @override
  bool get supportsPdf => false;

  @override
  Future<RecognitionResult> recognise({
    required Uint8List bytes,
    required String mimeType,
    required String fileName,
  }) async {
    if (!mimeType.startsWith('image/')) {
      throw const OcrException(
        'This file is a PDF without readable text. It is probably a scan, which '
        'cannot be read on this device. Try photographing the document instead.',
        kind: OcrFailureKind.unsupportedFile,
      );
    }

    // ML Kit reads from a file path, not from memory, so the bytes are written to
    // a temporary file first and removed afterwards. The temporary directory is
    // used deliberately rather than the documents directory: this copy is working
    // data, not something that should survive the operation.
    final directory = await getTemporaryDirectory();
    final file = File(p.join(
      directory.path,
      'ocr_${DateTime.now().microsecondsSinceEpoch}${p.extension(fileName)}',
    ));

    try {
      await file.writeAsBytes(bytes, flush: true);

      final recogniser = _recogniser ??=
          TextRecognizer(script: TextRecognitionScript.latin);

      final recognised =
          await recogniser.processImage(InputImage.fromFilePath(file.path));

      if (recognised.text.trim().isEmpty) {
        throw const OcrException(
          'No text was found in this image. Try a clearer photo with the whole '
          'document in frame.',
          kind: OcrFailureKind.noTextFound,
        );
      }

      // ML Kit reports no numeric confidence for Latin text, so rather than invent
      // one, the field is left null and the parser's own per-field scores carry the
      // uncertainty to the review screen. That is the honest arrangement: a made-up
      // 0.95 would make an unreadable receipt look verified.
      final lines = <String>[];
      for (final block in recognised.blocks) {
        for (final line in block.lines) {
          final text = line.text.trim();
          if (text.isNotEmpty) lines.add(text);
        }
      }

      _log.fine('Recognised ${lines.length} lines from $fileName');

      return RecognitionResult(
        provider: name,
        pages: [
          RecognisedPage(
            pageNumber: 1,
            text: recognised.text,
            confidence: null,
            lines: lines,
          ),
        ],
        confidence: null,
        metadata: {
          'method': 'on-device',
          'blocks': recognised.blocks.length,
          'lines': lines.length,
        },
      );
    } on OcrException {
      rethrow;
    } on Object catch (error, stack) {
      _log.warning('On-device recognition failed', error, stack);
      throw OcrException(
        'We could not read that image. Try a clearer photo.',
        kind: OcrFailureKind.unreadable,
        debugDetail: error.toString(),
      );
    } finally {
      // The working copy goes whatever happened. Leaving decrypted copies of
      // financial documents in a temporary directory is exactly the kind of
      // residue a finance app should not create.
      if (await file.exists()) {
        await file.delete().catchError((_) => file);
      }
    }
  }

  @override
  Future<void> dispose() async {
    await _recogniser?.close();
    _recogniser = null;
  }
}
