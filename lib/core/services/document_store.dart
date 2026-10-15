import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../errors/app_exception.dart';

final _log = Logger('DocumentStore');

/// Where uploaded documents live.
///
/// On the device, not in Cloud Storage. Firebase requires the Blaze plan for Cloud
/// Storage on projects created after October 2024, so on the free plan there is no
/// bucket to put them in — and storing a bank statement somewhere costs money to
/// keep is not a trade this app needs to make.
///
/// What this gains:
///
///   * **Financial documents never leave the phone.** Not uploaded, not held by a
///     third party, not reachable by a leaked URL. That is a stronger position than
///     either the signed-URL arrangement or the download-token one.
///   * **It is free, and it is fast.** No upload wait before the review screen can
///     show the receipt.
///
/// What it costs, stated plainly:
///
///   * **Documents do not sync between devices.** Signing in on a second phone
///     shows every transaction, with the receipt itself missing. The record of the
///     transaction is in Firestore; only the image is local.
///   * **Uninstalling the app deletes them.** The transactions survive; the scans
///     do not. Anything that matters should be kept elsewhere too.
///
/// The app states both of these where it matters rather than letting a user
/// discover them when a receipt is gone.
class DocumentStore {
  DocumentStore();

  Directory? _root;

  /// Files live under `<app documents>/finora_documents/<uid>/<documentId>/`.
  ///
  /// Scoped by user id so that two accounts on one device cannot read each other's
  /// files, which matters on a shared phone — and so sign-out can clear one without
  /// touching the other.
  Future<Directory> _directoryFor(String uid, String documentId) async {
    final root = _root ??= await getApplicationDocumentsDirectory();
    final directory =
        Directory(p.join(root.path, 'finora_documents', uid, documentId));

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  /// Saves a file and returns the path recorded against the document.
  ///
  /// The path stored is **relative** — `uid/documentId/file.jpg`. An absolute path
  /// would break on iOS, where the application container is reassigned a new
  /// directory on every update, silently detaching every receipt from its
  /// transaction.
  Future<String> save({
    required String uid,
    required String documentId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    try {
      final directory = await _directoryFor(uid, documentId);
      final safeName = sanitiseFileName(fileName);
      final file = File(p.join(directory.path, safeName));

      await file.writeAsBytes(bytes, flush: true);
      _log.fine('Stored $safeName (${bytes.length} bytes)');

      return p.join(uid, documentId, safeName).replaceAll(r'\', '/');
    } on Object catch (error, stack) {
      _log.warning('Could not store the document', error, stack);
      throw const FileException(
        'We could not save that file to this device. Check there is enough free '
        'space and try again.',
      );
    }
  }

  /// Reads a stored file back.
  ///
  /// Throws [NotFoundException] when it is gone — which happens legitimately: the
  /// app was reinstalled, or the record was synced from another device where the
  /// file was never stored.
  Future<Uint8List> read(String relativePath) async {
    final file = await _resolve(relativePath);

    if (!await file.exists()) {
      throw const NotFoundException(
        message: 'That document is not on this device. Receipts are stored '
            'locally, so they do not follow you between devices.',
      );
    }

    return file.readAsBytes();
  }

  /// Whether the file is present, for a preview that should degrade rather than
  /// error.
  Future<bool> exists(String relativePath) async {
    final file = await _resolve(relativePath);
    return file.exists();
  }

  Future<void> delete(String relativePath) async {
    try {
      final file = await _resolve(relativePath);
      if (await file.exists()) await file.delete();

      // Remove the document's folder too, so an empty directory is not left for
      // every receipt ever deleted.
      final parent = file.parent;
      if (await parent.exists() && await parent.list().isEmpty) {
        await parent.delete();
      }
    } on Object catch (error, stack) {
      // An orphaned file is a smaller problem than a failed delete, so this is
      // logged rather than thrown.
      _log.warning('Could not delete a stored document', error, stack);
    }
  }

  /// Removes every document belonging to one user.
  ///
  /// Called when an account is closed, and on sign-out, so a shared device does not
  /// leave the previous user's bank statements readable by the next.
  Future<void> deleteAllFor(String uid) async {
    try {
      final root = _root ??= await getApplicationDocumentsDirectory();
      final directory = Directory(p.join(root.path, 'finora_documents', uid));
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on Object catch (error, stack) {
      _log.warning('Could not clear stored documents', error, stack);
    }
  }

  Future<File> _resolve(String relativePath) async {
    final root = _root ??= await getApplicationDocumentsDirectory();
    return File(p.join(root.path, 'finora_documents', relativePath));
  }

  /// Strips anything that could be used for path traversal or that the filesystem
  /// would reject, while keeping the extension readable.
  static String sanitiseFileName(String fileName) {
    final collapsed = fileName
        .replaceAll(RegExp(r'[\\/]+'), '_')
        .replaceAll('..', '_')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final trimmed = collapsed.replaceAll(RegExp(r'^_+'), '');
    if (trimmed.isEmpty) return 'file';
    return trimmed.length <= 120 ? trimmed : trimmed.substring(0, 120);
  }
}
