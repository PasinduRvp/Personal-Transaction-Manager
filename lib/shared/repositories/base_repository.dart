import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logging/logging.dart';

import '../../core/errors/app_exception.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/services/firebase_service.dart';
import '../models/json_map.dart';
import 'relation_loader.dart';

/// Shared plumbing for every repository.
///
/// Three rules are enforced here rather than repeated in each method:
///
///   * Every failure leaves as an [AppException] with a user-safe message.
///     Nothing above this layer ever sees a `FirebaseException`.
///   * The user id always comes from the verified session, never from a caller
///     argument, so a repository cannot be asked to read someone else's data.
///     The security rules enforce the same rule server-side; this is the second
///     lock.
///   * Anything that must change more than one document goes through a callable
///     Cloud Function via [callFunction], not through a client-side batch. A
///     batch is atomic, but the *decision* of what to write would still be made
///     on a device that can be tampered with, and derived figures like an
///     account balance must not be writable from the client at all.
abstract class BaseRepository {
  BaseRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseService.firestore;

  final FirebaseFirestore _db;

  FirebaseFirestore get db => _db;

  Logger get log => Logger(runtimeType.toString());

  /// The signed-in user's id, or an [AuthenticationException].
  String get userId => FirebaseService.requireUserId();

  /// Accounts and categories, for the rows that reference them.
  ///
  /// `late` so a repository can be constructed before anyone signs in — reading
  /// [userId] eagerly would throw during provider wiring.
  late final RelationLoader relations =
      RelationLoader(firestore: _db, userId: userId);

  /// Runs [action], converting any failure into an [AppException].
  Future<T> guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on Object catch (error, stack) {
      throw ErrorMapper.map(error, stack);
    }
  }

  /// Runs a query and maps each document, folding the id into the map.
  Future<List<T>> fetchList<T>(
    Query<Map<String, dynamic>> query,
    T Function(Json) mapper,
  ) =>
      guard(() async {
        final snapshot = await query.get();
        return snapshot.docs
            .map((doc) => mapper(doc.asJson))
            .toList(growable: false);
      });

  /// Reads one document, or throws [NotFoundException].
  ///
  /// A missing document is not an error in Firestore — `get()` succeeds and
  /// returns a snapshot whose `exists` is false — so the check has to be
  /// explicit or a deleted row would surface as a model full of defaults.
  Future<T> fetchDoc<T>(
    DocumentReference<Map<String, dynamic>> ref,
    T Function(Json) mapper,
  ) =>
      guard(() async {
        final snapshot = await ref.get();
        if (!snapshot.exists) throw const NotFoundException();
        return mapper(snapshot.asJson);
      });

  /// Reads one document, or null when it does not exist.
  Future<T?> fetchDocOrNull<T>(
    DocumentReference<Map<String, dynamic>> ref,
    T Function(Json) mapper,
  ) =>
      guard(() async {
        final snapshot = await ref.get();
        return snapshot.exists ? mapper(snapshot.asJson) : null;
      });

  /// Watches a query, mapping each snapshot.
  ///
  /// Errors are mapped in the stream rather than thrown out of this method, so a
  /// permission change mid-stream surfaces as an [AppException] the UI can show
  /// instead of an unhandled error in the zone.
  Stream<List<T>> watchList<T>(
    Query<Map<String, dynamic>> query,
    T Function(Json) mapper,
  ) =>
      query.snapshots().map(
        (snapshot) =>
            snapshot.docs.map((doc) => mapper(doc.asJson)).toList(growable: false),
      ).handleError((Object error, StackTrace stack) {
        throw ErrorMapper.map(error, stack);
      });

  Stream<T?> watchDoc<T>(
    DocumentReference<Map<String, dynamic>> ref,
    T Function(Json) mapper,
  ) =>
      ref.snapshots().map(
        (snapshot) => snapshot.exists ? mapper(snapshot.asJson) : null,
      ).handleError((Object error, StackTrace stack) {
        throw ErrorMapper.map(error, stack);
      });

  /// Counts matching documents without reading them.
  ///
  /// An aggregation query is billed at a fraction of a document read, which
  /// matters for the badge counts the dashboard refreshes often.
  Future<int> countOf(Query<Map<String, dynamic>> query) => guard(() async {
        final result = await query.count().get();
        return result.count ?? 0;
      });

  /// A new document id, generated locally.
  ///
  /// Firestore ids are generated client-side, so a document's id is known before
  /// it is written. That is what lets a storage path and its document share an id
  /// without a round trip in between.
  String newId(CollectionReference<Map<String, dynamic>> collection) =>
      collection.doc().id;
}
