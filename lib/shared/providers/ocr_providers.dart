import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/app_exception.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/utils/money.dart';
import '../models/document.dart';
import '../models/ocr_job.dart';
import '../models/transaction_candidate.dart';
import '../repositories/document_repository.dart';
import '../repositories/ocr_repository.dart';
import 'account_providers.dart';
import 'auth_providers.dart';
import 'dashboard_providers.dart';
import 'repository_providers.dart';
import 'transaction_providers.dart';

/// Where an import currently is.
///
/// One enum rather than a handful of booleans, so the screen cannot render
/// "uploading" and "ready to review" at the same time.
enum ImportStage {
  idle,
  validating,
  uploading,
  processing,
  readyForReview,
  failed,
}

class ImportState {
  const ImportState({
    this.stage = ImportStage.idle,
    this.document,
    this.job,
    this.candidates = const [],
    this.failure,
    this.isReupload = false,
    this.existingDocumentId,
  });

  final ImportStage stage;
  final FinoraDocument? document;
  final OcrJob? job;
  final List<TransactionCandidate> candidates;

  /// The user-facing failure, already mapped to a friendly message and
  /// suggestions. Technical detail stays in the exception's debug field.
  final AppException? failure;

  /// True when this exact file content was uploaded before.
  final bool isReupload;
  final String? existingDocumentId;

  bool get isBusy =>
      stage == ImportStage.validating ||
      stage == ImportStage.uploading ||
      stage == ImportStage.processing;

  bool get hasCandidates => candidates.isNotEmpty;

  List<TransactionCandidate> get pendingCandidates => candidates
      .where((c) => c.status == OcrCandidateStatus.pending)
      .toList(growable: false);

  /// A statement produces many candidates and gets the selectable list; a
  /// receipt produces one and gets the single-transaction review form.
  bool get isMultiTransaction => candidates.length > 1;

  ImportState copyWith({
    ImportStage? stage,
    FinoraDocument? document,
    OcrJob? job,
    List<TransactionCandidate>? candidates,
    AppException? failure,
    bool? isReupload,
    String? existingDocumentId,
    bool clearFailure = false,
  }) =>
      ImportState(
        stage: stage ?? this.stage,
        document: document ?? this.document,
        job: job ?? this.job,
        candidates: candidates ?? this.candidates,
        failure: clearFailure ? null : (failure ?? this.failure),
        isReupload: isReupload ?? this.isReupload,
        existingDocumentId: existingDocumentId ?? this.existingDocumentId,
      );
}

/// Drives one document through the pipeline.
///
/// The controller stops at [ImportStage.readyForReview]. It has no method that
/// creates a transaction — that is [confirm], which is only reachable from the
/// review screen's button and which passes the values the user approved.
class ImportController extends Notifier<ImportState> {
  @override
  ImportState build() => const ImportState();

  /// Validates, uploads and reads a file.
  ///
  /// Each stage sets its own state before starting, so the screen can narrate
  /// what is happening rather than showing an undifferentiated spinner for
  /// however long a multi-page statement takes.
  Future<void> importFile({
    required Uint8List bytes,
    required String fileName,
  }) async {
    state = const ImportState(stage: ImportStage.validating);

    final documents = ref.read(documentRepositoryProvider);
    final ocr = ref.read(ocrRepositoryProvider);

    UploadedDocument uploaded;
    try {
      // Validate before uploading, so an unsupported or damaged file costs no
      // bandwidth and no provider call.
      documents.validateOnly(bytes: bytes, fileName: fileName);

      state = state.copyWith(stage: ImportStage.uploading);
      uploaded = await documents.upload(bytes: bytes, fileName: fileName);
    } on Object catch (error, stack) {
      state = ImportState(
        stage: ImportStage.failed,
        failure: ErrorMapper.map(error, stack),
      );
      return;
    }

    state = state.copyWith(
      stage: ImportStage.processing,
      document: uploaded.document,
      isReupload: uploaded.isReupload,
      existingDocumentId: uploaded.existingDocumentId,
    );

    try {
      var job = await ocr.startJob(documentId: uploaded.document.id);

      // The function usually finishes inside its own call, but a long statement
      // can outlive it; the job row is the authority either way.
      if (!job.status.isTerminal) {
        job = await ocr.awaitCompletion(job.id);
      }

      if (job.isFailed) {
        state = state.copyWith(
          stage: ImportStage.failed,
          job: job,
          failure: job.failure,
        );
        return;
      }

      final candidates = await ocr.fetchCandidates(job.id);

      state = state.copyWith(
        stage: ImportStage.readyForReview,
        job: job,
        candidates: candidates,
        clearFailure: true,
      );

      ref.invalidate(importHistoryProvider);
      ref.invalidate(documentsProvider);
    } on Object catch (error, stack) {
      state = state.copyWith(
        stage: ImportStage.failed,
        failure: ErrorMapper.map(error, stack),
      );
    }
  }

  /// Re-reads a document, creating a new job so the previous attempt stays in
  /// the history.
  Future<void> retry() async {
    final document = state.document;
    if (document == null) return;

    state = state.copyWith(
      stage: ImportStage.processing,
      clearFailure: true,
    );

    try {
      final ocr = ref.read(ocrRepositoryProvider);
      var job = await ocr.startJob(documentId: document.id, force: true);
      if (!job.status.isTerminal) {
        job = await ocr.awaitCompletion(job.id);
      }

      if (job.isFailed) {
        state = state.copyWith(
          stage: ImportStage.failed,
          job: job,
          failure: job.failure,
        );
        return;
      }

      state = state.copyWith(
        stage: ImportStage.readyForReview,
        job: job,
        candidates: await ocr.fetchCandidates(job.id),
        clearFailure: true,
      );
    } on Object catch (error, stack) {
      state = state.copyWith(
        stage: ImportStage.failed,
        failure: ErrorMapper.map(error, stack),
      );
    }
  }

  /// Loads an existing job, for reopening a previous import from the history.
  Future<void> loadJob(String jobId) async {
    state = const ImportState(stage: ImportStage.processing);
    try {
      final ocr = ref.read(ocrRepositoryProvider);
      final job = await ocr.fetchJob(jobId);
      final candidates = await ocr.fetchCandidates(job.id);

      state = ImportState(
        stage: job.isFailed ? ImportStage.failed : ImportStage.readyForReview,
        document: job.document,
        job: job,
        candidates: candidates,
        failure: job.failure,
      );
    } on Object catch (error, stack) {
      state = ImportState(
        stage: ImportStage.failed,
        failure: ErrorMapper.map(error, stack),
      );
    }
  }

  /// Saves a candidate's edits without creating a transaction.
  Future<void> saveDraft(TransactionCandidate candidate) async {
    final saved =
        await ref.read(ocrRepositoryProvider).saveCandidate(candidate);
    _replaceCandidate(saved);
  }

  /// Creates the transaction for a reviewed candidate.
  ///
  /// The only path from OCR output to the ledger, and it runs solely in response
  /// to the user pressing Confirm.
  Future<String> confirm({
    required TransactionCandidate candidate,
    required String accountId,
    required Money amount,
    required DateTime date,
    required TransactionType type,
    String? categoryId,
    String? merchant,
    String? description,
    PaymentMethod? paymentMethod,
    String? referenceNumber,
    String? notes,
    bool attachDocument = true,
  }) async {
    final transactionId =
        await ref.read(ocrRepositoryProvider).confirmCandidate(
              candidate: candidate,
              accountId: accountId,
              amount: amount,
              date: date,
              type: type,
              categoryId: categoryId,
              merchant: merchant,
              description: description,
              paymentMethod: paymentMethod,
              referenceNumber: referenceNumber,
              notes: notes,
              attachDocument: attachDocument,
            );

    await _refreshCandidates();
    _invalidateLedgerReaders();
    return transactionId;
  }

  /// Confirms several statement rows at once.
  Future<BatchConfirmResult> confirmMany(
    List<CandidateConfirmation> confirmations,
  ) async {
    final result = await ref
        .read(ocrRepositoryProvider)
        .confirmMany(confirmations: confirmations);

    await _refreshCandidates();
    _invalidateLedgerReaders();
    return result;
  }

  /// Dismisses a candidate. It stays in the history as ignored rather than being
  /// deleted, so the import record remains complete.
  Future<void> ignore(TransactionCandidate candidate) async {
    await ref.read(ocrRepositoryProvider).ignoreCandidate(candidate.id);
    await _refreshCandidates();
  }

  Future<void> cancel() async {
    final job = state.job;
    if (job != null && !job.status.isTerminal) {
      await ref.read(ocrRepositoryProvider).cancelJob(job.id);
    }
    state = const ImportState();
  }

  void reset() => state = const ImportState();

  void _replaceCandidate(TransactionCandidate updated) {
    state = state.copyWith(
      candidates: state.candidates
          .map((c) => c.id == updated.id ? updated : c)
          .toList(growable: false),
    );
  }

  Future<void> _refreshCandidates() async {
    final job = state.job;
    if (job == null) return;
    final candidates =
        await ref.read(ocrRepositoryProvider).fetchCandidates(job.id);
    state = state.copyWith(candidates: candidates);
  }

  void _invalidateLedgerReaders() {
    ref.invalidate(transactionListControllerProvider);
    ref.invalidate(accountsControllerProvider);
    ref.invalidate(dashboardControllerProvider);
    ref.invalidate(pendingCandidateCountProvider);
    ref.invalidate(importHistoryProvider);
  }
}

final importControllerProvider =
    NotifierProvider<ImportController, ImportState>(ImportController.new);

/// Live job status, so the processing screen advances its steps as the server
/// works rather than waiting for the HTTP call to return.
final jobStatusProvider =
    StreamProvider.family<OcrJob, String>((ref, jobId) {
  return ref.watch(ocrRepositoryProvider).watchJob(jobId);
});

/// Import history.
final importHistoryProvider = FutureProvider<List<OcrJob>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Future.value(const []);
  return ref.watch(ocrRepositoryProvider).fetchJobs();
});

/// Uploaded documents, for the documents screen.
final documentsProvider = FutureProvider<List<FinoraDocument>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Future.value(const []);
  return ref.watch(documentRepositoryProvider).fetchAll();
});

final documentByIdProvider =
    FutureProvider.family<FinoraDocument, String>((ref, id) {
  return ref.watch(documentRepositoryProvider).fetchById(id);
});

/// A document's bytes, for viewing it.
///
/// There is no URL equivalent. A Firebase download URL carries a token that works
/// for anyone holding it, with no expiry, so a forwarded link would hand over a
/// bank statement permanently; reading through the SDK keeps each access checked
/// against the storage rules and the caller's token.
final documentBytesProvider =
    FutureProvider.family<Uint8List, FinoraDocument>((ref, document) {
  return ref.watch(documentRepositoryProvider).download(document);
});

/// Preview bytes, or null when there is nothing to draw — a PDF, or a file that
/// could not be read.
final documentPreviewProvider =
    FutureProvider.family<Uint8List?, FinoraDocument>((ref, document) {
  return ref.watch(documentRepositoryProvider).previewBytes(document);
});

/// Raw OCR text, for the review screen's "what we read" panel.
///
/// Keyed by job: a document read twice has two sets of output, and the panel
/// should show the one belonging to the job being reviewed.
final ocrResultsProvider =
    FutureProvider.family<List<OcrResult>, String>((ref, jobId) {
  return ref.watch(ocrRepositoryProvider).fetchResults(jobId);
});

/// Candidates for one job.
final jobCandidatesProvider =
    FutureProvider.family<List<TransactionCandidate>, String>((ref, jobId) {
  return ref.watch(ocrRepositoryProvider).fetchCandidates(jobId);
});

/// How many candidates are still awaiting review, for the dashboard prompt.
final pendingCandidateCountProvider = FutureProvider<int>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Future.value(0);
  return ref.watch(ocrRepositoryProvider).pendingCandidateCount();
});

/// Possible duplicates for a candidate, looked up when the review screen opens.
final candidateDuplicatesProvider =
    FutureProvider.family<List<DuplicateMatch>, TransactionCandidate>(
        (ref, candidate) async {
  final amount = candidate.amount;
  final date = candidate.transactionDate;
  if (amount == null || date == null) return const [];

  return ref.watch(transactionRepositoryProvider).findDuplicates(
        amount: amount,
        date: date,
        merchant: candidate.merchant,
        accountId: candidate.accountId,
        reference: candidate.referenceNumber,
      );
});
