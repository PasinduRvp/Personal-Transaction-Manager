import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/constants/enums.dart';
import '../models/app_notification.dart';
import 'auth_providers.dart';
import 'profile_providers.dart';
import 'repository_providers.dart';

final _log = Logger('BudgetAlerts');

/// Raises any budget thresholds the latest write has crossed.
///
/// Called after a transaction is saved, in place of the Firestore trigger the
/// paid plan used. It reads the spend figures *after* the write has committed,
/// which is the only point at which they are correct.
///
/// Never throws and never rethrows. This runs after the user's transaction has
/// already been saved successfully, and a notification that could not be
/// written is not a reason to show them a failure — the sweep simply catches up
/// on the next write.
Future<void> sweepBudgetAlerts(Ref ref) async {
  try {
    final settings = ref.read(settingsControllerProvider).valueOrNull;
    // Settings carry the per-kind mute flags. Without them the sweep cannot
    // tell which alerts the user wants, and guessing would be worse than
    // waiting for the next write.
    if (settings == null) return;

    final progress = await ref.read(budgetRepositoryProvider).fetchProgress(
          fallbackCurrency: ref.read(currencyProvider),
        );
    if (progress.isEmpty) return;

    final raised = await ref.read(budgetAlertServiceProvider).sweep(
          progress: progress,
          settings: settings,
        );
    if (raised == 0) return;

    // The budgets themselves changed too — their alert state was stamped — so
    // the list is refreshed along with the notification badge.
    ref.invalidate(notificationsControllerProvider);
    ref.invalidate(unreadNotificationCountProvider);
  } on Object catch (error, stack) {
    // Reading a disposed provider throws, which happens routinely when the
    // user leaves the screen before the sweep finishes. Nothing to do about
    // it, and nothing worth telling them.
    _log.fine('Budget alert sweep skipped', error, stack);
  }
}

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

// ---------------------------------------------------------------------------
// Filtering
// ---------------------------------------------------------------------------

/// Which category the notification centre is filtered to. Null means all.
final notificationCategoryFilterProvider =
    StateProvider<NotificationCategory?>((ref) => null);

/// Whether the list is restricted to unread notifications.
final notificationUnreadOnlyProvider = StateProvider<bool>((ref) => false);

/// How many notifications fall into each category, for the filter chip counts.
///
/// Counted over everything rather than over the filtered list, so the chips
/// keep saying how much is behind them while one of them is selected.
final notificationCategoryCountsProvider =
    Provider<Map<NotificationCategory, int>>((ref) {
  final all = ref.watch(notificationsControllerProvider).valueOrNull ?? const [];
  final counts = <NotificationCategory, int>{};
  for (final notification in all) {
    final category = notification.kind.category;
    counts[category] = (counts[category] ?? 0) + 1;
  }
  return counts;
});

/// The notifications the centre should currently show.
///
/// Filtering lives here rather than in the widget so the empty state can tell
/// "you have none at all" apart from "none match this filter" — which are
/// different situations and deserve different messages.
final filteredNotificationsProvider = Provider<List<AppNotification>>((ref) {
  final all = ref.watch(notificationsControllerProvider).valueOrNull ?? const [];
  final category = ref.watch(notificationCategoryFilterProvider);
  final unreadOnly = ref.watch(notificationUnreadOnlyProvider);

  return all.where((notification) {
    if (unreadOnly && notification.isRead) return false;
    if (category != null && notification.kind.category != category) return false;
    return true;
  }).toList(growable: false);
});
