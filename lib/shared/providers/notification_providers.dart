import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_notification.dart';
import 'auth_providers.dart';
import 'repository_providers.dart';

class NotificationsController extends AsyncNotifier<List<AppNotification>> {
  @override
  Future<List<AppNotification>> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const [];
    return ref.watch(notificationRepositoryProvider).fetchAll();
  }

  /// Marks one read, applied locally first so the row stops looking unread the
  /// instant it is tapped.
  Future<void> markRead(String id) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current
            .map((n) => n.id == id
                ? n.copyWith(isRead: true, readAt: DateTime.now())
                : n)
            .toList(),
      );
    }

    try {
      await ref.read(notificationRepositoryProvider).markRead(id);
    } finally {
      ref.invalidate(unreadNotificationCountProvider);
    }
  }

  Future<void> markAllRead() async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current
            .map((n) => n.copyWith(isRead: true, readAt: DateTime.now()))
            .toList(),
      );
    }

    try {
      await ref.read(notificationRepositoryProvider).markAllRead();
    } finally {
      ref.invalidate(unreadNotificationCountProvider);
    }
  }

  Future<void> delete(String id) async {
    await ref.read(notificationRepositoryProvider).delete(id);
    ref.invalidateSelf();
    ref.invalidate(unreadNotificationCountProvider);
    await future;
  }

  Future<void> clearRead() async {
    await ref.read(notificationRepositoryProvider).clearRead();
    ref.invalidateSelf();
    await future;
  }

  Future<void> refresh() async {
    state = const AsyncValue<List<AppNotification>>.loading();
    ref.invalidateSelf();
    await future;
  }
}

final notificationsControllerProvider =
    AsyncNotifierProvider<NotificationsController, List<AppNotification>>(
  NotificationsController.new,
);

/// Unread count for the app bar badge.
final unreadNotificationCountProvider = FutureProvider<int>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Future.value(0);
  return ref.watch(notificationRepositoryProvider).unreadCount();
});

/// Live unread count, so a budget alert raised by the database appears without
/// the user pulling to refresh.
final unreadNotificationStreamProvider = StreamProvider<int>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream<int>.value(0);
  return ref.watch(notificationRepositoryProvider).watchUnreadCount();
});

/// Unread notifications only, for the "new" section of the list.
final unreadNotificationsProvider = Provider<List<AppNotification>>((ref) {
  final all = ref.watch(notificationsControllerProvider).valueOrNull ?? const [];
  return all.where((n) => !n.isRead).toList(growable: false);
});
