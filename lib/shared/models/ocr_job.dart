import 'package:equatable/equatable.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/app_exception.dart';
import 'document.dart';
import 'json_map.dart';

/// A row of `public.ocr_jobs` — one attempt at reading one document.
///
/// Jobs are kept even after they succeed: they are the audit trail that
/// explains where an imported transaction came from, and re-running OCR creates
/// a new job rather than overwriting the old one.
class OcrJob extends Equatable {
  const OcrJob({
    required this.id,
    required this.userId,
    required this.documentId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.provider,
    this.fileType,
    this.startedAt,
    this.completedAt,
    this.errorCode,
    this.errorMessage,
    this.pagesProcessed = 0,
    this.pageCount,
    this.candidateCount = 0,
    this.confirmedCount = 0,
    this.usedEmbeddedText = false,
    this.document,
  });

  final String id;
  final String userId;
  final String documentId;
  final OcrJobStatus status;

  /// Which provider handled the job, e.g. `google-vision`. Recorded so a
  /// provider swap is visible in the history.
  final String? provider;
  final String? fileType;
  final DateTime? startedAt;
  final DateTime? completedAt;

  /// Machine-readable failure reason; mapped to a friendly message client-side.
  final String? errorCode;

  /// Server-side detail. Never rendered directly — see [failure].
  final String? errorMessage;

  final int pagesProcessed;
  final int? pageCount;

  /// How many transaction candidates the parser produced.
  final int candidateCount;

  /// How many of those the user has since confirmed.
  final int confirmedCount;

  /// True when a text-layer PDF was read directly, with no OCR pass needed.
  final bool usedEmbeddedText;

  final FinoraDocument? document;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isRunning => !status.isTerminal;
  bool get isFailed => status == OcrJobStatus.failed;

  Duration? get duration {
    final start = startedAt;
    final end = completedAt;
    if (start == null) return null;
    return (end ?? DateTime.now()).difference(start);
  }

  /// Progress across the pipeline stages, for the processing screen.
  double get progressFraction {
    switch (status) {
      case OcrJobStatus.queued:
        return 0.15;
      case OcrJobStatus.processing:
        final total = pageCount ?? 0;
        if (total <= 0) return 0.5;
        return (0.25 + 0.6 * (pagesProcessed / total)).clamp(0.25, 0.9);
      case OcrJobStatus.completed:
      case OcrJobStatus.partiallyCompleted:
        return 1;
      case OcrJobStatus.failed:
      case OcrJobStatus.cancelled:
        return 1;
    }
  }

  /// A user-facing exception built from the stored error code. Server messages
  /// are never surfaced verbatim.
  OcrException? get failure {
    if (!isFailed) return null;
    final kind = OcrFailureKind.fromWire(errorCode);
    return OcrException(
      _messageFor(kind),
      kind: kind,
      debugDetail: errorMessage,
    );
  }

  static String _messageFor(OcrFailureKind kind) => switch (kind) {
        OcrFailureKind.unreadable =>
          "We couldn't read this document clearly.",
        OcrFailureKind.noTextFound =>
          "We couldn't find any text in this document.",
        OcrFailureKind.unsupportedFile =>
          'This file type is not supported.',
        OcrFailureKind.corruptFile =>
          "This file appears to be damaged and couldn't be opened.",
        OcrFailureKind.tooManyPages =>
          'This document has too many pages to process at once.',
        OcrFailureKind.timeout =>
          'Reading this document took too long.',
        OcrFailureKind.providerUnavailable =>
          'Document reading is temporarily unavailable.',
        OcrFailureKind.unknown =>
          "We couldn't read this document.",
      };

  /// Which pipeline stages are complete, for the stepped progress display.
  ///
  /// The job row only exists once the upload succeeded, so the first stage is
  /// always complete.
  List<OcrStage> get stages {
    final reading = status == OcrJobStatus.processing;
    final done = status.isSuccessful;
    return [
      const OcrStage('Uploading', true, false),
      OcrStage('Reading document', reading || done,
          status == OcrJobStatus.queued),
      OcrStage('Extracting transactions', done, reading),
      OcrStage('Preparing review', done, false),
    ];
  }

  factory OcrJob.fromJson(Json json) {
    final documentJson = json.relation('document');
    return OcrJob(
      id: json.str('id'),
      userId: json.str('user_id'),
      documentId: json.str('document_id'),
      status: OcrJobStatus.fromWire(json.strOrNull('status')),
      provider: json.strOrNull('provider'),
      fileType: json.strOrNull('file_type'),
      startedAt: json.dateOrNull('started_at'),
      completedAt: json.dateOrNull('completed_at'),
      errorCode: json.strOrNull('error_code'),
      errorMessage: json.strOrNull('error_message'),
      pagesProcessed: json.intVal('pages_processed'),
      pageCount: json.intOrNull('page_count'),
      candidateCount: json.intVal('candidate_count'),
      confirmedCount: json.intVal('confirmed_count'),
      usedEmbeddedText: json.boolVal('used_embedded_text'),
      document:
          documentJson == null ? null : FinoraDocument.fromJson(documentJson),
      createdAt: json.dateVal('created_at'),
      updatedAt: json.dateVal('updated_at'),
    );
  }

  @override
  List<Object?> get props => [
        id,
        documentId,
        status,
        provider,
        startedAt,
        completedAt,
        errorCode,
        pagesProcessed,
        pageCount,
        candidateCount,
        confirmedCount,
        usedEmbeddedText,
      ];
}

/// One row of the stepped progress display on the processing screen.
class OcrStage {
  const OcrStage(this.label, this.isComplete, this.isActive);

  final String label;
  final bool isComplete;
  final bool isActive;
}

/// A row of `public.ocr_results` — the raw provider output.
///
/// Stored separately from the transaction so a correction never destroys the
/// evidence: the original text remains available for auditing and for
/// re-parsing with an improved parser.
class OcrResult extends Equatable {
  const OcrResult({
    required this.id,
    required this.documentId,
    required this.rawText,
    required this.createdAt,
    this.jobId,
    this.confidence,
    this.provider,
    this.pageNumber,
    this.metadata = const {},
  });

  final String id;
  final String documentId;
  final String? jobId;

  /// Exactly what the provider returned, unmodified.
  final String rawText;

  /// Overall page confidence, 0–1.
  final double? confidence;
  final String? provider;
  final int? pageNumber;
  final Json metadata;
  final DateTime createdAt;

  bool get isEmpty => rawText.trim().isEmpty;

  int get lineCount => rawText.split('\n').where((l) => l.trim().isNotEmpty).length;

  factory OcrResult.fromJson(Json json) => OcrResult(
        id: json.str('id'),
        documentId: json.str('document_id'),
        jobId: json.strOrNull('job_id'),
        rawText: json.str('raw_text'),
        confidence: json.dblOrNull('confidence'),
        provider: json.strOrNull('provider'),
        pageNumber: json.intOrNull('page_number'),
        metadata: json.jsonVal('metadata'),
        createdAt: json.dateVal('created_at'),
      );

  @override
  List<Object?> get props =>
      [id, documentId, jobId, rawText, confidence, provider, pageNumber];
}
