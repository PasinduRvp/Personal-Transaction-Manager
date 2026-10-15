import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path/path.dart' as p;

import '../../core/errors/app_exception.dart';
import '../../core/services/firebase_service.dart';
import '../../core/services/image_preprocessor.dart';
import '../../core/services/document_store.dart';
import '../models/json_map.dart';
import '../models/profile.dart';
import 'base_repository.dart';

/// The user's own document at `users/{uid}`, and their settings at
/// `users/{uid}/settings/app`.
///
/// Both are created by the `onUserCreate` Cloud Function the moment the auth
/// account exists, so the app never has to decide whether to seed them — which
/// is what kept two devices from each writing a default profile.
class ProfileRepository extends BaseRepository {
  ProfileRepository({super.firestore, DocumentStore? store})
      : _store = store ?? DocumentStore();

  final DocumentStore _store;

  DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseService.userDoc(userId);

  DocumentReference<Map<String, dynamic>> get _settingsDoc =>
      FirebaseService.settingsDoc(userId);

  /// Reads the profile.
  ///
  /// No cache fallback: Firestore serves this from its own on-device copy when
  /// the network is gone, so the greeting and the user's currency survive going
  /// offline without a second cache to keep in sync.
  Future<Profile> fetch() => fetchDoc(_doc, Profile.fromJson);

  Stream<Profile?> watch() => watchDoc(_doc, Profile.fromJson);

  Future<Profile> update(Profile profile) => guard(() async {
        await _doc.update({...profile.toUpdateJson(), ...updatedFields()});
        return fetch();
      });

  Future<UserSettings> fetchSettings() async {
    try {
      return await fetchDoc(_settingsDoc, UserSettings.fromJson);
    } on NotFoundException {
      return UserSettings(userId: userId);
    }
  }

  Future<UserSettings> updateSettings(UserSettings settings) =>
      guard(() async {
        await _settingsDoc.set({
          'user_id': userId,
          ...settings.toUpdateJson(),
          ...updatedFields(),
        }, SetOptions(merge: true));
        return fetchSettings();
      });

  /// Stores a new avatar on the device and records its path.
  ///
  /// Local, like the documents, and for the same reason: Cloud Storage is a paid
  /// feature. An avatar is also the one piece of this app's data nobody loses sleep
  /// over — it does not follow the user to a second device, and the profile screen
  /// falls back to their initials, which is a perfectly good avatar.
  Future<Profile> uploadAvatar({
    required Uint8List bytes,
    required String fileName,
  }) =>
      guard(() async {
        final compressed = await ImagePreprocessor.compressForStorage(
          bytes,
          maxBytes: 400 * 1024,
        );

        final extension = p.extension(fileName).toLowerCase();
        final safeExtension =
            ['.jpg', '.jpeg', '.png', '.webp'].contains(extension)
                ? extension
                : '.jpg';

        // A fixed id per user, so a new avatar replaces the old one rather than
        // accumulating a folder of every picture ever chosen.
        final path = await _store.save(
          uid: userId,
          documentId: 'avatar',
          fileName: 'profile$safeExtension',
          bytes: compressed,
        );

        await _doc.update({
          'profile_image_url': path,
          ...updatedFields(),
        });

        return fetch();
      });

  Future<Profile> removeAvatar(Profile current) => guard(() async {
        final path = current.profileImageUrl;
        if (path != null && path.isNotEmpty) {
          await _store.delete(path);
        }
        await _doc.update({
          'profile_image_url': FieldValue.delete(),
          ...updatedFields(),
        });
        return fetch();
      });

  /// The avatar's bytes, for rendering with `Image.memory`.
  ///
  /// Returns null rather than throwing when it is missing: the profile screen falls
  /// back to initials, and a picture that did not follow the user to this device
  /// should not take the screen down.
  Future<Uint8List?> avatarBytes(String? storagePath) async {
    if (storagePath == null || storagePath.isEmpty) return null;
    try {
      return await _store.read(storagePath);
    } on Object catch (error, stack) {
      log.fine('Could not load avatar', error, stack);
      return null;
    }
  }

  /// Every collection this user owns, as one JSON payload.
  ///
  /// Read from the client because there is no server to assemble it. The shape is
  /// therefore defined here, and each collection is capped — an export is a file
  /// someone downloads, and reading an unbounded history would both take a while
  /// and eat into a day's free read quota.
  ///
  /// The files themselves are not included: they are the user's own documents,
  /// already on their device, and inlining them would make the payload enormous.
  Future<Json> exportData() => guard(() async {
        final uid = userId;

        final profile = await FirebaseService.userDoc(uid).get();
        final settings = await FirebaseService.settingsDoc(uid).get();

        final collections = <String, Query<Map<String, dynamic>>>{
          'accounts': FirebaseService.accounts(uid),
          'categories': FirebaseService.categories(uid),
          'transactions': FirebaseService.transactions(uid),
          'budgets': FirebaseService.budgets(uid),
          'savingsGoals': FirebaseService.savingsGoals(uid),
          'bills': FirebaseService.bills(uid),
          'subscriptions': FirebaseService.subscriptions(uid),
          'recurringTransactions': FirebaseService.recurring(uid),
          'documents': FirebaseService.documents(uid),
          'ocrJobs': FirebaseService.ocrJobs(uid),
          'ocrCandidates': FirebaseService.ocrCandidates(uid),
          'notifications': FirebaseService.notifications(uid),
          'monthlySummaries': FirebaseService.monthlySummaries(uid),
        };

        final data = <String, dynamic>{
          'exported_at': DateTime.now().toIso8601String(),
          'format_version': 2,
          'profile': profile.exists ? profile.asJson : null,
          'settings': settings.exists ? settings.asJson : null,
        };

        for (final entry in collections.entries) {
          final snapshot = await entry.value.limit(5000).get();
          data[entry.key] = snapshot.docs.map((doc) => doc.asJson).toList();
        }

        // Splits live under each transaction, so they are collected separately
        // rather than being silently left out of the export.
        final splits = <Json>[];
        final splitParents = await FirebaseService.transactions(uid)
            .where('is_split', isEqualTo: true)
            .limit(500)
            .get();

        for (final parent in splitParents.docs) {
          final lines = await FirebaseService.splits(parent.id, uid).get();
          splits.addAll(lines.docs.map((doc) => doc.asJson));
        }
        data['transactionSplits'] = splits;

        return data;
      });

  /// Erases the user's application data but leaves the account open.
  ///
  /// For someone who wants a clean slate without losing their sign-in.
  Future<Json> deleteData() => guard(() async {
        final result = await _eraseEverything(keepProfile: true);
        await _doc.update({
          'seeded_at': FieldValue.delete(),
          ...updatedFields(),
        });
        return result;
      });

  /// Closes the account: documents first, then the Firebase user.
  ///
  /// Firestore cascades nothing, so each collection has to be walked explicitly —
  /// a deleted user's transactions, splits, contributions and OCR results would
  /// otherwise remain as documents nobody can reach but which still count against
  /// storage.
  ///
  /// The order matters. Data first, the auth user last, so a failure partway leaves
  /// an account that can still sign in and retry rather than a locked-out user
  /// whose records are half gone.
  ///
  /// The email is checked against the signed-in account's own address. That is a
  /// guard against a confirmation dialog having been bypassed, not a substitute for
  /// one — the user has already typed their address into the dialog by this point.
  Future<Json> deleteAccountCompletely({required String confirmEmail}) =>
      guard(() async {
        final user = FirebaseService.user;
        final email = user?.email;

        if (user == null || email == null) {
          throw const AuthenticationException(
            'Your session has expired. Please sign in again.',
          );
        }

        if (confirmEmail.trim().toLowerCase() != email.toLowerCase()) {
          throw const ValidationException(
            'The email address did not match the signed-in account.',
          );
        }

        final result = await _eraseEverything(keepProfile: false);

        // Last, and deliberately so. Firebase requires a recent sign-in for this;
        // a stale session surfaces as `requires-recent-login`, which the mapper
        // turns into a request to sign in again — with the data already gone but
        // the account still reachable to finish the job.
        await user.delete();

        return result;
      });

  /// Deletes every document this user owns, and every file they uploaded.
  Future<Json> _eraseEverything({required bool keepProfile}) async {
    final uid = userId;
    var deleted = 0;

    // Subcollections go with their parents, named explicitly because there is no
    // way to discover them from a document reference.
    deleted += await _deleteWithChildren(
      FirebaseService.transactions(uid),
      (id) => FirebaseService.splits(id, uid),
    );
    deleted += await _deleteWithChildren(
      FirebaseService.savingsGoals(uid),
      (id) => FirebaseService.contributions(id, uid),
    );
    deleted += await _deleteWithChildren(
      FirebaseService.ocrJobs(uid),
      (id) => FirebaseService.ocrResults(id, uid),
    );

    for (final collection in [
      FirebaseService.accounts(uid),
      FirebaseService.categories(uid),
      FirebaseService.budgets(uid),
      FirebaseService.bills(uid),
      FirebaseService.subscriptions(uid),
      FirebaseService.recurring(uid),
      FirebaseService.documents(uid),
      FirebaseService.ocrCandidates(uid),
      FirebaseService.notifications(uid),
      FirebaseService.monthlySummaries(uid),
    ]) {
      deleted += await _deleteAll(collection);
    }

    await FirebaseService.settingsDoc(uid).delete().catchError((_) {});

    // The documents stored on this device. A failure here leaves an orphaned file
    // rather than a record pointing at nothing, which is the safer of the two, so
    // it does not abort the rest.
    await _store.deleteAllFor(uid);

    if (!keepProfile) {
      await FirebaseService.userDoc(uid).delete().catchError((_) {});
    }

    return <String, dynamic>{'deleted': deleted, 'accountClosed': !keepProfile};
  }

  /// Deletes a collection in batches.
  ///
  /// Batched at 400 to stay under Firestore's 500-write limit, and looped so a long
  /// collection finishes rather than being half-cleared.
  Future<int> _deleteAll(Query<Map<String, dynamic>> query) async {
    var deleted = 0;

    while (true) {
      final page = await query.limit(400).get();
      if (page.docs.isEmpty) return deleted;

      final batch = db.batch();
      for (final doc in page.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      deleted += page.docs.length;

      if (page.docs.length < 400) return deleted;
    }
  }

  Future<int> _deleteWithChildren(
    CollectionReference<Map<String, dynamic>> collection,
    Query<Map<String, dynamic>> Function(String parentId) children,
  ) async {
    var deleted = 0;

    while (true) {
      final page = await collection.limit(100).get();
      if (page.docs.isEmpty) return deleted;

      for (final doc in page.docs) {
        deleted += await _deleteAll(children(doc.id));
      }

      final batch = db.batch();
      for (final doc in page.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      deleted += page.docs.length;
    }
  }
}
