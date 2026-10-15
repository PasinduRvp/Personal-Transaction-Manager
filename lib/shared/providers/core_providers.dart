import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/cache_service.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/firebase_service.dart';
import '../../core/services/document_store.dart';

/// The Firestore instance. Overridden in tests with one pointed at the emulator,
/// or with a fake.
final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseService.firestore,
);

/// Small key-value cache for things that are not Firestore documents — the last
/// signed-in user's display name for the sign-in screen, and the like.
///
/// Financial data no longer goes through this: Firestore's own offline
/// persistence keeps the documents it has read and serves them without a
/// connection, which is what this cache used to be for.
///
/// `SharedPreferences` needs an await, so this is created in `main` and injected
/// as an override. Reading it before that override is a programming error rather
/// than something to paper over with a null check, so it throws.
final cacheServiceProvider = Provider<CacheService>((ref) {
  throw StateError(
    'cacheServiceProvider was read before it was overridden in main(). '
    'Call CacheService.create() during startup and pass it as an override.',
  );
});

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  throw StateError(
    'connectivityServiceProvider was read before it was overridden in main().',
  );
});

/// Where uploaded documents are kept.
///
/// On the device rather than in Cloud Storage, which Firebase reserves for the
/// paid plan. See `DocumentStore` for what that gains and what it costs.
final documentStoreProvider = Provider<DocumentStore>((ref) => DocumentStore());

/// Whether the device currently has a network path.
///
/// Used to decide when to *prefer* cached data and to show the offline banner —
/// never as proof a request will succeed. Requests are still attempted, and
/// their failures still handled.
final isOnlineProvider = StreamProvider<bool>((ref) {
  final connectivity = ref.watch(connectivityServiceProvider);
  return Stream<bool>.value(connectivity.isOnline)
      .followedBy(connectivity.onStatusChange);
});

extension _StreamPrepend<T> on Stream<T> {
  Stream<T> followedBy(Stream<T> next) async* {
    yield* this;
    yield* next;
  }
}

/// Convenience synchronous read of the online state, defaulting to online so a
/// first frame does not render an offline banner before the check completes.
final isOfflineProvider = Provider<bool>((ref) {
  return ref.watch(isOnlineProvider).maybeWhen(
        data: (online) => !online,
        orElse: () => false,
      );
});
