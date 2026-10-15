import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart' as crypto;

import '../../core/constants/enums.dart';
import '../../core/errors/app_exception.dart';
import '../../core/services/firebase_service.dart';
import '../../core/services/document_store.dart';
import '../../core/utils/validators.dart';
import '../models/document.dart';
import '../models/json_map.dart';
import 'base_repository.dart';

/// Result of uploading a file, before OCR runs.
class UploadedDocument {
  const UploadedDocument({
    required this.document,
    required this.isReupload,
    this.existingDocumentId,
  });

  final FinoraDocument document;

  /// True when the same file content was uploaded before.
  final bool isReupload;
  final String? existingDocumentId;
}

/// Uploaded documents, at `users/{uid}/documents`, with their files in Cloud
/// Storage under `documents/{uid}/{documentId}/`.
class DocumentRepository extends BaseRepository {
  DocumentRepository({super.firestore, DocumentStore? store})
      : _store = store ?? DocumentStore();

  final DocumentStore _store;

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseService.documents(userId);

  Future<List<FinoraDocument>> fetchAll({
    bool includeArchived = false,
    int limit = 100,
  }) {
    final query = includeArchived
        ? _col.orderBy('created_at', descending: true).limit(limit)
        : _col
            .where('is_archived', isEqualTo: false)
            .orderBy('created_at', descending: true)
            .limit(limit);
    return fetchList(query, FinoraDocument.fromJson);
  }

  Future<FinoraDocument> fetchById(String id) =>
      fetchDoc(_col.doc(id), FinoraDocument.fromJson);

  /// Live document, so the review screen sees `ocr_status` change as the function
  /// works through the file instead of needing a pull-to-refresh.
  Stream<FinoraDocument?> watchById(String id) =>
      watchDoc(_col.doc(id), FinoraDocument.fromJson);

  /// Validates a file, stores it on the device, and records it in Firestore.
  ///
  /// The file stays on the phone; only its metadata syncs. Firebase requires the
  /// paid plan for Cloud Storage, and keeping financial documents local is the
  /// better answer anyway — a bank statement that is never uploaded cannot be
  /// exposed by a leaked link.
  ///
  /// The document id is generated before the write so the stored path can contain
  /// it. Firestore hands out ids locally with no round trip, which is what makes
  /// the path deterministic and a failed attempt retryable to the same place.
  ///
  /// The original bytes are stored untouched. Preprocessing for recognition happens
  /// on a copy, so the receipt the user can reopen is exactly what they uploaded.
  Future<UploadedDocument> upload({
    required Uint8List bytes,
    required String fileName,
    DocumentType documentType = DocumentType.unknown,
  }) =>
      guard(() async {
        final validation = FileValidator.validate(
          fileName: fileName,
          sizeBytes: bytes.length,
          headBytes: bytes.take(16).toList(),
        );

        // Content hash, so uploading the same receipt twice is detectable before it
        // becomes a duplicate transaction.
        final checksum = crypto.sha256.convert(bytes).toString();
        final existing = await _findByChecksum(checksum);

        final ref = _col.doc();
        final documentId = ref.id;

        final storagePath = await _store.save(
          uid: userId,
          documentId: documentId,
          fileName: validation.fileName,
          bytes: bytes,
        );

        final document = FinoraDocument(
          id: documentId,
          userId: userId,
          fileName: validation.fileName,
          storagePath: storagePath,
          mimeType: validation.mimeType,
          fileSize: validation.sizeBytes,
          documentType: documentType,
          ocrStatus: OcrJobStatus.queued,
          checksum: checksum,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        try {
          await ref.set({
            ...document.toInsertJson(),
            'user_id': userId,
            'is_archived': false,
            ...createdFields(),
          });

          return UploadedDocument(
            document: await fetchById(documentId),
            isReupload: existing != null,
            existingDocumentId: existing?.id,
          );
        } on Object {
          // The record failed, so the stored file has nothing pointing at it.
          // Remove it rather than leaving a file the app can never show or delete.
          await _store.delete(storagePath);
          rethrow;
        }
      });

  Future<FinoraDocument?> _findByChecksum(String checksum) => guard(() async {
        final snapshot = await _col
            .where('checksum', isEqualTo: checksum)
            .where('is_archived', isEqualTo: false)
            .orderBy('created_at', descending: true)
            .limit(1)
            .get();
        if (snapshot.docs.isEmpty) return null;
        return FinoraDocument.fromJson(snapshot.docs.first.asJson);
      });

  /// The document's bytes, read from the device.
  Future<Uint8List> download(FinoraDocument document) =>
      guard(() => _store.read(document.storagePath));

  /// Preview bytes, or null when there is nothing to draw.
  ///
  /// PDFs return null: rendering one needs a PDF engine, and the preview falls back
  /// to a file card. A missing file also returns null rather than throwing — a
  /// record synced from another device has no file here, and the review screen
  /// should say so rather than break.
  Future<Uint8List?> previewBytes(FinoraDocument document) async {
    if (document.isPdf) return null;
    try {
      return await _store.read(document.storagePath);
    } on Object catch (error, stack) {
      log.fine('Could not load document preview', error, stack);
      return null;
    }
  }

  /// Whether the file behind a record is present on this device.
  ///
  /// Used by the UI to explain an absent preview rather than showing a broken one.
  Future<bool> isAvailableLocally(FinoraDocument document) =>
      _store.exists(document.storagePath);

  Future<FinoraDocument> setType(String id, DocumentType type) =>
      guard(() async {
        await _col.doc(id).update({
          'document_type': type.wire,
          ...updatedFields(),
        });
        return fetchById(id);
      });

  Future<FinoraDocument> setArchived(String id, {required bool archived}) =>
      guard(() async {
        await _col.doc(id).update({
          'is_archived': archived,
          ...updatedFields(),
        });
        return fetchById(id);
      });

  /// Deletes a document and its stored file.
  ///
  /// Transactions that referenced it keep existing with their attachment cleared:
  /// a receipt is evidence for a transaction, not the transaction itself, and
  /// deleting a photo must not delete a record of spending. The clearing is done
  /// by the `onDocumentDeleted` trigger, which can find those transactions without
  /// the client having to enumerate them.
  Future<void> delete(FinoraDocument document) => guard(() async {
        // Firestore cascades nothing, so the jobs, results and unconfirmed
        // candidates that belong to this document are removed explicitly. A
        // confirmed candidate is kept: by then it is the audit trail of a
        // transaction that exists.
        await _deleteOcrTrail(document.id);

        // Transactions keep existing with their attachment cleared. A receipt is
        // evidence for a transaction, not the transaction itself, and deleting a
        // photo must never delete a record of spending.
        final attached = await FirebaseService.transactions(userId)
            .where('document_id', isEqualTo: document.id)
            .get();

        if (attached.docs.isNotEmpty) {
          final batch = db.batch();
          for (final doc in attached.docs) {
            batch.update(doc.reference, {
              'document_id': FieldValue.delete(),
              ...updatedFields(),
            });
          }
          await batch.commit();
        }

        await _col.doc(document.id).delete();

        // The file last. If this fails it is orphaned, rather than the record
        // pointing at nothing — the safer of the two failures.
        await _store.delete(document.storagePath);
      });

  Future<void> _deleteOcrTrail(String documentId) async {
    final jobs = await FirebaseService.ocrJobs(userId)
        .where('document_id', isEqualTo: documentId)
        .get();

    for (final job in jobs.docs) {
      final results = await FirebaseService.ocrResults(job.id, userId).get();
      final batch = db.batch();
      for (final result in results.docs) {
        batch.delete(result.reference);
      }
      batch.delete(job.reference);
      await batch.commit();
    }

    final candidates = await FirebaseService.ocrCandidates(userId)
        .where('document_id', isEqualTo: documentId)
        .where('status', whereIn: ['PENDING', 'IGNORED', 'DUPLICATE'])
        .get();

    if (candidates.docs.isEmpty) return;

    final batch = db.batch();
    for (final doc in candidates.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  /// How many transactions reference this document.
  Future<int> attachmentCount(String documentId) => countOf(
        FirebaseService.transactions(userId)
            .where('document_id', isEqualTo: documentId),
      );

  /// Base64 of a document, for embedding a receipt image in a PDF report.
  Future<String> base64(FinoraDocument document) async {
    final bytes = await download(document);
    return base64Encode(bytes);
  }

  /// Validates a file without uploading it, for the pre-upload confirmation
  /// sheet.
  FileValidationResult validateOnly({
    required Uint8List bytes,
    required String fileName,
  }) {
    if (bytes.isEmpty) {
      throw const FileException('That file is empty. Choose another file.');
    }
    return FileValidator.validate(
      fileName: fileName,
      sizeBytes: bytes.length,
      headBytes: bytes.take(16).toList(),
    );
  }
}
