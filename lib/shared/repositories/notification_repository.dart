import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/firebase_service.dart';
import '../models/app_notification.dart';
import 'base_repository.dart';

/// Reads the notification centre, at `users/{uid}/notifications`.
///
/// There is no create method, and the security rules deny client creates
/// outright: notifications are written by Firestore triggers and the scheduled
/// function. That is deliberate — an alert that says "budget exceeded" should be
/// the server's judgement, not something a client can fabricate. Clients may
/// only mark one read or delete it.
class NotificationRepository extends BaseRepository {
  NotificationRepository({super.firestore});

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseService.notifications(userId);

  Future<List<AppNotification>> fetchAll({int limit = 60}) => fetchList(
        _col.orderBy('created_at', descending: true).limit(limit),
        AppNotification.fromJson,
      );

  Future<int> unreadCount() =>
      countOf(_col.where('is_read', isEqualTo: false));

  /// Live unread count for the app bar badge.
  ///
  /// Capped at 99 documents: the badge renders "99+" past that, so reading more
  /// would be paying for a number nobody sees.
  Stream<int> watchUnreadCount() => _col
      .where('is_read', isEqualTo: false)
      .limit(99)
      .snapshots()
      .map((snapshot) => snapshot.docs.length);

  Future<void> markRead(String id) => guard(() async {
        await _col.doc(id).update({
          'is_read': true,
          'read_at': FieldValue.serverTimestamp(),
        });
      });

  /// Marks every unread notification read in one batch.
  ///
  /// Firestore has no `update … where`, so the matching documents have to be read
  /// first. The limit of 400 keeps the batch under its 500-write ceiling; the
  /// loop repeats until none are left, so a long-neglected list still clears.
  Future<void> markAllRead() => guard(() async {
        while (true) {
          final unread = await _col
              .where('is_read', isEqualTo: false)
              .limit(400)
              .get();
          if (unread.docs.isEmpty) return;

          final batch = db.batch();
          for (final doc in unread.docs) {
            batch.update(doc.reference, {
              'is_read': true,
              'read_at': FieldValue.serverTimestamp(),
            });
          }
          await batch.commit();

          if (unread.docs.length < 400) return;
        }
      });

  Future<void> delete(String id) => guard(() => _col.doc(id).delete());

  Future<void> clearRead() => guard(() async {
        while (true) {
          final read = await _col
              .where('is_read', isEqualTo: true)
              .limit(400)
              .get();
          if (read.docs.isEmpty) return;

          final batch = db.batch();
          for (final doc in read.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();

          if (read.docs.length < 400) return;
        }
      });
}
