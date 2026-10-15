import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;

import '../../core/constants/app_constants.dart';
import '../../core/constants/enums.dart';
import '../../core/errors/app_exception.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/ocr/parsing/parser.dart';
import '../../core/ocr/text_recogniser.dart';
import '../../core/services/document_store.dart';
import '../../core/services/firebase_service.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/money.dart';
import '../models/json_map.dart';
import '../models/budget.dart';
import '../models/document.dart';
import '../models/ocr_job.dart';
import '../models/transaction.dart';
import '../models/transaction_candidate.dart';
import 'base_repository.dart';
import 'ledger_writer.dart';

/// The client half of the OCR pipeline.
///
/// This repository can start a job, watch it, read what it produced, and confirm
/// a candidate the user has reviewed. What it cannot do is turn OCR output into a
/// transaction on its own: the only write path to `transactions` from here is
/// [confirmCandidate], which is called from the review screen's Confirm button,
/// and the Cloud Function behind it refuses to run without an amount, an account
/// and a date. The security rules also forbid this client from writing a
/// candidate's `status` or its `created_transaction_id`, so "confirmed" is a state
/// only the server can produce.
///
/// Collections: jobs at `users/{uid}/ocrJobs`, the provider's raw output at
/// `users/{uid}/ocrJobs/{jobId}/results`, and candidates at
/// `users/{uid}/ocrCandidates`. Candidates sit at the top level rather than under
/// their job because the dashboard counts every pending candidate across all
/// imports, which a subcollection would turn into a collection-group query.
class OcrRepository extends BaseRepository {
  OcrRepository({
    super.firestore,
    DocumentStore? store,
    TextRecogniser? recogniser,
  })  : _store = store ?? DocumentStore(),
        _recogniser = recogniser ?? MlKitTextRecogniser();

  final DocumentStore _store;
  final TextRecogniser _recogniser;

  CollectionReference<Map<String, dynamic>> get _documents =>
      FirebaseService.documents(userId);

  CollectionReference<Map<String, dynamic>> get _jobs =>
      FirebaseService.ocrJobs(userId);

  CollectionReference<Map<String, dynamic>> get _candidates =>
      FirebaseService.ocrCandidates(userId);

  // -------------------------------------------------------------------------
  // Starting and watching a job
  // -------------------------------------------------------------------------

  /// Reads an uploaded document, on this device.
  ///
  ///     validate → read bytes → recognise → classify → parse → write candidates
  ///
  /// What this deliberately does *not* do is create a transaction. It writes
  /// candidates and stops. Promoting one into the ledger requires
  /// [confirmCandidate], which runs only when the user presses Confirm on the
  /// review screen. That boundary is the product's central promise, and it is
  /// enforced here by omission.
  ///
  /// **There is no API key anywhere in this app.** The specification required that
  /// OCR credentials never ship in the client; without a server to hold one, the
  /// honest answer is not to have a key at all. ML Kit runs the recogniser on the
  /// phone, so the document is never uploaded to be read and there is no quota to
  /// spend.
  Future<OcrJob> startJob({
    required String documentId,
    bool force = false,
  }) =>
      guard(() async {
        final documentSnapshot = await _documents.doc(documentId).get();
        if (!documentSnapshot.exists) throw const NotFoundException();

        final document = FinoraDocument.fromJson(documentSnapshot.asJson);

        // Re-reading is allowed but must be explicit, so a retried tap does not
        // silently produce a second set of candidates for the same receipt.
        if (!force) {
          final existing = await _jobs
              .where('document_id', isEqualTo: documentId)
              .where('status', whereIn: [
                OcrJobStatus.queued.wire,
                OcrJobStatus.processing.wire,
                OcrJobStatus.completed.wire,
                OcrJobStatus.partiallyCompleted.wire,
              ])
              .orderBy('created_at', descending: true)
              .limit(1)
              .get();

          if (existing.docs.isNotEmpty) {
            return fetchJob(existing.docs.first.id);
          }
        }

        final jobRef = _jobs.doc();
        await jobRef.set({
          'user_id': userId,
          'document_id': documentId,
          'status': OcrJobStatus.processing.wire,
          'provider': _recogniser.name,
          'file_type': document.mimeType,
          'started_at': FieldValue.serverTimestamp(),
          'candidate_count': 0,
          ...createdFields(),
        });

        try {
          await _runPipeline(jobRef.id, document);
          return fetchJob(jobRef.id);
        } on Object catch (error, stack) {
          await _failJob(jobRef.id, documentId, error, stack);
          rethrow;
        }
      });

  /// The pipeline itself.
  ///
  /// Returns the number of candidates written.
  Future<int> _runPipeline(String jobId, FinoraDocument document) async {
    final bytes = await _store.read(document.storagePath);

    if (bytes.isEmpty) {
      throw const OcrException(
        'That file is empty.',
        kind: OcrFailureKind.noTextFound,
      );
    }

    final recognised = await _recogniser.recognise(
      bytes: bytes,
      mimeType: document.mimeType,
      fileName: document.fileName,
    );

    await _jobs.doc(jobId).update({
      'pages_processed': recognised.pages.length,
      'page_count': recognised.pages.length,
      'used_embedded_text': false,
      'provider': recognised.provider,
    });

    final rawText = recognised.fullText;
    if (rawText.trim().isEmpty) {
      throw const OcrException(
        'No text was found in this document.',
        kind: OcrFailureKind.noTextFound,
      );
    }

    // The recognised text is stored per page, before it is interpreted, so the
    // evidence survives even if parsing throws — and so an improved parser can be
    // re-run over it later without re-reading the image. The rules make these
    // documents immutable: a correction on the review screen must never be able to
    // rewrite what the recogniser actually returned.
    final resultsBatch = db.batch();
    for (final page in recognised.pages) {
      resultsBatch.set(
        FirebaseService.ocrResults(jobId, userId).doc('${page.pageNumber}'),
        {
          'user_id': userId,
          'document_id': document.id,
          'job_id': jobId,
          'raw_text': page.text,
          'confidence': page.confidence,
          'provider': recognised.provider,
          'page_number': page.pageNumber,
          'metadata': recognised.metadata,
          ...createdFields(),
        },
      );
    }
    await resultsBatch.commit();

    // Classify and parse. Pure functions over the text, with no I/O — which is why
    // they are unit-tested against fixed strings and did not change when the
    // recogniser moved on-device.
    final profile = await FirebaseService.userDoc(userId).get();
    final currency = profile.asJson.str('default_currency', fallback: 'LKR');

    final parsed = parseDocument(
      rawText,
      ParseOptions(defaultCurrency: currency, preferDayFirst: true),
    );

    await _documents.doc(document.id).update({
      'document_type': parsed.documentKind,
      'ocr_status': OcrJobStatus.completed.wire,
      'page_count': recognised.pages.length,
      ...updatedFields(),
    });

    // Map suggested category names onto the user's own categories. A name that
    // does not exist is dropped rather than created: the parser does not get to add
    // rows to someone's category list.
    final categories = await FirebaseService.categories(userId)
        .where('is_archived', isEqualTo: false)
        .get();

    final categoryByName = <String, String>{
      for (final doc in categories.docs)
        '${doc.asJson.str('kind', fallback: 'EXPENSE')}:'
                '${doc.asJson.str('name').toLowerCase()}':
            doc.id,
    };

    if (parsed.candidates.isNotEmpty) {
      final batch = db.batch();

      for (final candidate in parsed.candidates) {
        final kind =
            candidate.transactionType == 'INCOME' ? 'INCOME' : 'EXPENSE';
        final categoryId = candidate.suggestedCategoryName == null
            ? null
            : categoryByName[
                '$kind:${candidate.suggestedCategoryName!.toLowerCase()}'];

        final fieldConfidence =
            Map<String, double>.from(candidate.fieldConfidence);
        if (candidate.suggestedCategoryName != null && categoryId == null) {
          fieldConfidence.remove('category');
        }

        batch.set(_candidates.doc(), {
          'user_id': userId,
          'job_id': jobId,
          'document_id': document.id,
          'transaction_type': candidate.transactionType,
          // Null when the parser could not find an amount, and left null on
          // purpose: the review screen requires the user to supply one, and a zero
          // would look like a figure that had been read.
          minorKey('amount'): candidate.amount == null
              ? null
              : Money.fromMajor(candidate.amount!, candidate.currency)
                  .minorUnits,
          'currency': candidate.currency,
          'merchant': candidate.merchant,
          'description': candidate.description,
          'transaction_date': candidate.transactionDate == null
              ? null
              : Timestamp.fromDate(DateTime.parse(candidate.transactionDate!)),
          'suggested_category_id': categoryId,
          'payment_method': candidate.paymentMethod,
          'reference_number': candidate.referenceNumber,
          // The account is left null on purpose. A document does not say which of
          // the user's accounts it belongs to, and guessing would put money in the
          // wrong place. The review screen requires the user to choose one.
          'account_id': null,
          'confidence': candidate.confidence,
          'field_confidence': fieldConfidence,
          'status': OcrCandidateStatus.pending.wire,
          'created_transaction_id': null,
          'duplicate_of_transaction_id': null,
          'page_number': candidate.pageNumber,
          'raw_line': candidate.rawLine,
          'sort_order': candidate.sortOrder,
          ...createdFields(),
        });
      }

      await batch.commit();
    }

    // A document read successfully with nothing in it is "completed" with zero
    // candidates rather than "failed": the read worked, there was just nothing to
    // import, and the user should see that distinction.
    await _jobs.doc(jobId).update({
      'status': parsed.candidates.isEmpty
          ? OcrJobStatus.completed.wire
          : OcrJobStatus.partiallyCompleted.wire,
      'candidate_count': parsed.candidates.length,
      'completed_at': FieldValue.serverTimestamp(),
    });

    return parsed.candidates.length;
  }

  Future<void> _failJob(
    String jobId,
    String documentId,
    Object error,
    StackTrace stack,
  ) async {
    final kind = error is OcrException ? error.kind : OcrFailureKind.unknown;

    // Logged with its detail; the UI only ever sees the user-facing message. The
    // detail can name file paths, which do not belong on screen.
    log.warning('OCR job $jobId failed (${kind.name})', error, stack);

    await _jobs.doc(jobId).update({
      'status': OcrJobStatus.failed.wire,
      'error_code': kind.name.toUpperCase(),
      'error_message':
          error is AppException ? error.message : 'We could not read this file.',
      'completed_at': FieldValue.serverTimestamp(),
    }).catchError((_) {});

    await _documents.doc(documentId).update({
      'ocr_status': OcrJobStatus.failed.wire,
      ...updatedFields(),
    }).catchError((_) {});
  }

  Future<OcrJob> fetchJob(String jobId) => guard(() async {
        final snapshot = await _jobs.doc(jobId).get();
        if (!snapshot.exists) throw const NotFoundException();
        return OcrJob.fromJson(await _withDocument(snapshot.asJson));
      });

  /// Import history, newest first.
  Future<List<OcrJob>> fetchJobs({int limit = 50}) => guard(() async {
        final snapshot = await _jobs
            .orderBy('created_at', descending: true)
            .limit(limit)
            .get();
        if (snapshot.docs.isEmpty) return const <OcrJob>[];

        // One read per referenced document would be `limit` extra reads; the
        // documents are fetched as one batch instead.
        final documents = await _documentLookup(
          snapshot.docs
              .map((doc) => doc.asJson.strOrNull('document_id'))
              .whereType<String>()
              .toSet(),
        );

        return snapshot.docs.map((doc) {
          final json = doc.asJson;
          final document = documents[json.strOrNull('document_id')];
          return OcrJob.fromJson({
            ...json,
            if (document != null) 'document': document,
          });
        }).toList(growable: false);
      });

  /// Live status of one job, for the processing screen.
  ///
  /// The rules confine this listener to the caller's own subcollection, so it can
  /// only ever carry their job.
  Stream<OcrJob> watchJob(String jobId) => _jobs
      .doc(jobId)
      .snapshots()
      .where((snapshot) => snapshot.exists)
      .asyncMap((snapshot) async => OcrJob.fromJson(
            await _withDocument(snapshot.asJson),
          ))
      .handleError((Object error, StackTrace stack) {
        throw ErrorMapper.map(error, stack);
      });

  /// Polls until the job reaches a terminal state.
  ///
  /// Kept as a fallback where the listener cannot be established, and to put a
  /// hard ceiling on how long the UI will wait: without it a stuck job would spin
  /// forever behind a progress indicator with nothing to tell the user.
  Future<OcrJob> awaitCompletion(
    String jobId, {
    Duration timeout = AppConstants.ocrPollTimeout,
    Duration interval = AppConstants.ocrPollInterval,
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final job = await fetchJob(jobId);
      if (job.status.isTerminal) return job;
      await Future<void>.delayed(interval);
    }

    throw const OcrException(
      'Reading this document is taking longer than expected.',
      kind: OcrFailureKind.timeout,
    );
  }

  /// Cancels a job.
  ///
  /// A callable because cancelling also releases the document's status and
  /// discards any candidates already written, and those must change together or
  /// the review screen would offer candidates from a job the user abandoned.
  Future<void> cancelJob(String jobId) => guard(() async {
        // The job, its raw output and its unconfirmed candidates go together.
        // Leaving the candidates would mean the review screen kept offering
        // transactions from an import the user abandoned. A confirmed one is left
        // alone: by then it is a transaction with a receipt, not a proposal.
        final batch = db.batch();

        final candidates = await _candidates
            .where('job_id', isEqualTo: jobId)
            .where('status', whereIn: [
              OcrCandidateStatus.pending.wire,
              OcrCandidateStatus.duplicate.wire,
            ])
            .get();
        for (final doc in candidates.docs) {
          batch.delete(doc.reference);
        }

        final results = await FirebaseService.ocrResults(jobId, userId).get();
        for (final doc in results.docs) {
          batch.delete(doc.reference);
        }

        batch.update(_jobs.doc(jobId), {
          'status': OcrJobStatus.cancelled.wire,
          'completed_at': FieldValue.serverTimestamp(),
          'candidate_count': 0,
        });

        await batch.commit();
      });

  // -------------------------------------------------------------------------
  // Raw results
  // -------------------------------------------------------------------------

  /// The provider's unmodified output, for the "raw text" panel on the review
  /// screen and for support requests.
  ///
  /// Keyed by job rather than by document: a document re-read with a different
  /// provider has two sets of output, and the panel should show the one belonging
  /// to the job being reviewed.
  Future<List<OcrResult>> fetchResults(String jobId) => fetchList(
        FirebaseService.ocrResults(jobId, userId).orderBy('page_number'),
        OcrResult.fromJson,
      );

  // -------------------------------------------------------------------------
  // Candidates
  // -------------------------------------------------------------------------

  Future<List<TransactionCandidate>> fetchCandidates(
    String jobId, {
    bool includeResolved = true,
  }) =>
      guard(() async {
        final query = includeResolved
            ? _candidates
                .where('job_id', isEqualTo: jobId)
                .orderBy('sort_order')
                .orderBy('created_at')
            : _candidates
                .where('job_id', isEqualTo: jobId)
                .where('status', isEqualTo: OcrCandidateStatus.pending.wire)
                .orderBy('sort_order')
                .orderBy('created_at');

        final snapshot = await query.get();
        if (snapshot.docs.isEmpty) return const <TransactionCandidate>[];

        final index = await relations.load();
        return snapshot.docs
            .map((doc) => TransactionCandidate.fromJson(index.attach(
                  doc.asJson,
                  categoryIdKey: 'suggested_category_id',
                )))
            .toList(growable: false);
      });

  /// How many candidates are still awaiting review, for the dashboard prompt.
  Future<int> pendingCandidateCount() => countOf(
        _candidates
            .where('status', isEqualTo: OcrCandidateStatus.pending.wire),
      );

  Future<TransactionCandidate> fetchCandidate(String id) => guard(() async {
        final snapshot = await _candidates.doc(id).get();
        if (!snapshot.exists) throw const NotFoundException();
        final index = await relations.load();
        return TransactionCandidate.fromJson(index.attach(
          snapshot.asJson,
          categoryIdKey: 'suggested_category_id',
        ));
      });

  /// Saves the user's edits to a candidate without confirming it — the review
  /// screen's "Save as draft".
  ///
  /// Only the candidate document changes. The raw OCR output is immutable and the
  /// rules deny writes to it, so a correction never destroys the evidence the
  /// candidate came from.
  Future<TransactionCandidate> saveCandidate(
    TransactionCandidate candidate,
  ) =>
      guard(() async {
        await _candidates.doc(candidate.id).update({
          ...candidate.toUpdateJson(),
          ...updatedFields(),
        });
        return fetchCandidate(candidate.id);
      });

  /// Dismisses a candidate the user does not want.
  ///
  /// A status change rather than a delete: the candidate is the record of what the
  /// import proposed, and keeping it is what stops the same line being offered
  /// again every time the statement is re-read.
  Future<void> ignoreCandidate(String candidateId) => guard(() async {
        final ref = _candidates.doc(candidateId);
        final snapshot = await ref.get();

        if (!snapshot.exists) throw const NotFoundException();

        if (snapshot.asJson.strOrNull('created_transaction_id') != null) {
          throw const ValidationException(
            'This one has already been imported. Delete the transaction instead.',
          );
        }

        await ref.update({
          'status': OcrCandidateStatus.ignored.wire,
          'ignored_at': FieldValue.serverTimestamp(),
          ...updatedFields(),
        });
      });

  /// Promotes a reviewed candidate into a real transaction.
  ///
  /// The values passed here are the ones the user approved on screen, not what the
  /// parser produced. The function repeats the required-field checks and is the
  /// only writer of `created_transaction_id`, so the link between a candidate and
  /// the transaction it became cannot be forged — and a candidate cannot be marked
  /// confirmed without a transaction existing.
  Future<String> confirmCandidate({
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
    TransactionStatus status = TransactionStatus.confirmed,
  }) =>
      guard(() async {
        // Required, every time, and checked here rather than only in the form. A
        // candidate with no amount, no date or no account is exactly what must not
        // become a transaction.
        if (amount.isZero || amount.isNegative) {
          throw const ValidationException(
            'Enter an amount greater than zero before saving.',
          );
        }
        if (type.isTransfer) {
          throw const ValidationException(
            'An imported document cannot be recorded as a transfer. Record it as '
            'income or an expense, or create the transfer yourself.',
          );
        }

        final candidateRef = _candidates.doc(candidate.id);

        // Read first to short-circuit a retry. Confirming twice would create a
        // second transaction for the same receipt, and the second would look
        // exactly as legitimate as the first.
        final existing = await candidateRef.get();
        if (!existing.exists) throw const NotFoundException();

        final existingTransactionId =
            existing.asJson.strOrNull('created_transaction_id');
        if (existingTransactionId != null) return existingTransactionId;

        final budgets = await _activeBudgets();
        final transactionRef = FirebaseService.transactions(userId).doc();

        await db.runTransaction((tx) async {
          final snapshot = await tx.get(candidateRef);
          final account =
              await tx.get(FirebaseService.accounts(userId).doc(accountId));

          if (!snapshot.exists) throw const NotFoundException();
          if (!account.exists) {
            throw const ValidationException('That account no longer exists.');
          }

          final data = snapshot.asJson;
          final candidateStatus =
              OcrCandidateStatus.fromWire(data.strOrNull('status'));

          // Re-checked inside the transaction, because the read above is not part
          // of it. Two devices confirming the same candidate at the same moment is
          // unlikely but not impossible, and the loser must not write a second
          // transaction.
          if (data.strOrNull('created_transaction_id') != null) {
            throw const ValidationException(
              'That one has just been imported. Pull to refresh to see it.',
            );
          }
          if (candidateStatus == OcrCandidateStatus.ignored) {
            throw const ValidationException(
              'That extracted transaction was dismissed. Restore it first if you '
              'want to import it.',
            );
          }

          final accountCurrency =
              account.asJson.str('currency', fallback: amount.currency);
          if (accountCurrency != amount.currency) {
            throw ValidationException(
              'That account holds $accountCurrency. Choose an account in '
              '${amount.currency}, or record the converted amount yourself so the '
              'rate is the one you were given.',
            );
          }

          final documentId = data.strOrNull('document_id');

          // The transaction and the candidate's status are written together. That
          // pair is what guarantees a confirmed candidate always points at a
          // transaction that exists, and a transaction from an import always has a
          // candidate behind it — the invariant Postgres held in a check constraint
          // and the paid plan held in a Cloud Function.
          //
          // The values written are the ones the user approved, not what the parser
          // produced. The candidate keeps its own figures for the audit trail.
          tx.set(transactionRef, {
            'user_id': userId,
            'account_id': accountId,
            'category_id': categoryId,
            'type': type.wire,
            ...moneyFields('amount', amount),
            'description': description,
            'merchant': merchant,
            'payment_method': paymentMethod?.wire,
            'transaction_date': Timestamp.fromDate(date),
            'notes': notes,
            // The receipt travels with the transaction it produced, which is the
            // point of the import: the evidence stays attached to the record.
            'document_id': attachDocument ? documentId : null,
            // Recorded as the kind of import it came from, so the transaction
            // detail screen can say where the figure originated.
            'source': TransactionSource.ocrImage.wire,
            'status': status.wire,
            'reference_number': referenceNumber,
            'is_split': false,
            'search_terms': searchTerms(
              [merchant, description, notes, referenceNumber],
              prefixed: [merchant],
            ),
            ...createdFields(),
          });

          tx.update(candidateRef, {
            'status': OcrCandidateStatus.confirmed.wire,
            'created_transaction_id': transactionRef.id,
            'account_id': accountId,
            'confirmed_at': FieldValue.serverTimestamp(),
            ...updatedFields(),
          });

          LedgerWriter.apply(
            tx,
            userId: userId,
            before: null,
            after: LedgerEffect(
              accountId: accountId,
              categoryId: categoryId,
              type: type,
              status: status,
              currency: amount.currency,
              amountMinor: amount.minorUnits.abs(),
              date: date,
              merchant: merchant,
              paymentMethod: paymentMethod?.wire,
              transferDirection: null,
            ),
            budgets: budgets,
          );
        });

        return transactionRef.id;
      });

  Future<List<Budget>> _activeBudgets() async {
    final snapshot = await FirebaseService.budgets(userId).get();
    return snapshot.docs
        .map((doc) => Budget.fromJson(doc.asJson))
        .where((b) => !b.isArchived)
        .toList(growable: false);
  }

  /// Confirms several candidates from one statement import.
  ///
  /// Each is confirmed individually so one bad row cannot block the rest, and the
  /// caller is told exactly which ones failed rather than being left to guess from
  /// a single error.
  Future<BatchConfirmResult> confirmMany({
    required List<CandidateConfirmation> confirmations,
  }) async {
    final createdIds = <String>[];
    final failures = <String, AppException>{};

    for (final confirmation in confirmations) {
      try {
        final id = await confirmCandidate(
          candidate: confirmation.candidate,
          accountId: confirmation.accountId,
          amount: confirmation.amount,
          date: confirmation.date,
          type: confirmation.type,
          categoryId: confirmation.categoryId,
          merchant: confirmation.merchant,
          description: confirmation.description,
          paymentMethod: confirmation.paymentMethod,
          referenceNumber: confirmation.referenceNumber,
          attachDocument: confirmation.attachDocument,
        );
        createdIds.add(id);
      } on AppException catch (error) {
        failures[confirmation.candidate.id] = error;
      }
    }

    return BatchConfirmResult(
      createdTransactionIds: createdIds,
      failures: failures,
    );
  }

  /// The transaction a candidate produced, for the "already imported" state.
  Future<Transaction?> fetchCreatedTransaction(
    TransactionCandidate candidate,
  ) async {
    final id = candidate.createdTransactionId;
    if (id == null) return null;

    final snapshot =
        await FirebaseService.transactions(userId).doc(id).get();
    if (!snapshot.exists) return null;

    final index = await relations.load();
    return Transaction.fromJson(index.attach(snapshot.asJson));
  }

  /// Helper used by the review screen to show what the parser proposed for a date
  /// that could not be read.
  static DateTime suggestedDate(TransactionCandidate candidate) =>
      candidate.transactionDate ?? AppDateUtils.startOfDay(DateTime.now());

  // -------------------------------------------------------------------------
  // Document attachment
  // -------------------------------------------------------------------------

  /// Attaches the referenced document to a job's map, replacing the join Postgres
  /// used to do.
  Future<Json> _withDocument(Json job) async {
    final documentId = job.strOrNull('document_id');
    if (documentId == null) return job;

    final snapshot =
        await FirebaseService.documents(userId).doc(documentId).get();
    if (!snapshot.exists) return job;

    return <String, dynamic>{...job, 'document': snapshot.asJson};
  }

  Future<Map<String, Json>> _documentLookup(Set<String> ids) async {
    if (ids.isEmpty) return const {};

    final documents = <String, Json>{};
    final all = ids.toList();

    // `whereIn` takes at most 30 values, so the ids go in chunks.
    for (var start = 0; start < all.length; start += 30) {
      final chunk = all.sublist(
        start,
        start + 30 > all.length ? all.length : start + 30,
      );
      final snapshot = await FirebaseService.documents(userId)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snapshot.docs) {
        documents[doc.id] = doc.asJson;
      }
    }

    return documents;
  }
}

/// One row of a batch confirmation, carrying the user's approved values.
class CandidateConfirmation {
  const CandidateConfirmation({
    required this.candidate,
    required this.accountId,
    required this.amount,
    required this.date,
    required this.type,
    this.categoryId,
    this.merchant,
    this.description,
    this.paymentMethod,
    this.referenceNumber,
    this.attachDocument = true,
  });

  final TransactionCandidate candidate;
  final String accountId;
  final Money amount;
  final DateTime date;
  final TransactionType type;
  final String? categoryId;
  final String? merchant;
  final String? description;
  final PaymentMethod? paymentMethod;
  final String? referenceNumber;
  final bool attachDocument;
}

class BatchConfirmResult {
  const BatchConfirmResult({
    required this.createdTransactionIds,
    required this.failures,
  });

  final List<String> createdTransactionIds;

  /// Candidate id to the reason it could not be saved.
  final Map<String, AppException> failures;

  int get successCount => createdTransactionIds.length;
  int get failureCount => failures.length;
  bool get isCompleteSuccess => failures.isEmpty;
  bool get isCompleteFailure => createdTransactionIds.isEmpty;

  String get summary {
    if (isCompleteSuccess) {
      return successCount == 1
          ? '1 transaction saved'
          : '$successCount transactions saved';
    }
    if (isCompleteFailure) {
      return 'No transactions could be saved';
    }
    return '$successCount saved, $failureCount could not be saved';
  }
}
