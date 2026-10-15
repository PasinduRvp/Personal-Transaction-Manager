import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/firebase_service.dart';
import '../models/json_map.dart';

/// Stands in for the joins Firestore does not have.
///
/// A transaction references an account and a category by id. Postgres returned
/// them in the same query; Firestore cannot, and reading each one per row would
/// turn a 20-row list into 60 billed reads and 40 extra round trips.
///
/// So the two small, slow-changing collections are read once — a few dozen
/// documents between them — and matched in memory. Models read the attached maps
/// through `Json.relation`, which is the same shape the embedded Postgres rows
/// arrived in, so no model needed changing.
///
/// **The cache is shared and expires.** Repositories are long-lived providers, so a
/// per-instance cache with no expiry would hold the first snapshot for the life of
/// the app: renaming a category would leave every transaction list showing the old
/// name until a restart. It is therefore static — one copy for all repositories, so
/// a write through one invalidates what the others see — with a short time limit as
/// a backstop for a change made on another device.
class RelationLoader {
  RelationLoader({required this.firestore, required this.userId});

  final FirebaseFirestore firestore;
  final String userId;

  /// Long enough to cover one screen's worth of reads, short enough that a change
  /// made on another device appears without the user wondering why it has not.
  static const Duration _maxAge = Duration(seconds: 30);

  static String? _cachedUserId;
  static RelationIndex? _cached;
  static DateTime? _cachedAt;

  /// Loads accounts and categories, reusing a recent result.
  ///
  /// [refresh] forces a reload, which a caller wants immediately after creating a
  /// category so the new name resolves in the same breath.
  Future<RelationIndex> load({bool refresh = false}) async {
    final cached = _cached;
    final cachedAt = _cachedAt;

    final usable = cached != null &&
        cachedAt != null &&
        _cachedUserId == userId &&
        DateTime.now().difference(cachedAt) < _maxAge;

    if (usable && !refresh) return cached;

    final (accounts, categories) = await (
      FirebaseService.accounts(userId).get(),
      FirebaseService.categories(userId).get(),
    ).wait;

    final index = RelationIndex(
      accounts: {for (final doc in accounts.docs) doc.id: doc.asJson},
      categories: {for (final doc in categories.docs) doc.id: doc.asJson},
    );

    _cached = index;
    _cachedAt = DateTime.now();
    _cachedUserId = userId;
    return index;
  }

  /// Drops the shared cache.
  ///
  /// Called by the account and category repositories after any write, so a rename
  /// or a new account is reflected on the next read rather than up to [_maxAge]
  /// later. Also called on sign-out: the next user must not see the previous one's
  /// account names.
  static void invalidate() {
    _cached = null;
    _cachedAt = null;
    _cachedUserId = null;
  }
}

/// The loaded lookups, plus the attachment step.
class RelationIndex {
  const RelationIndex({required this.accounts, required this.categories});

  const RelationIndex.empty()
      : accounts = const {},
        categories = const {};

  final Map<String, Json> accounts;
  final Map<String, Json> categories;

  Json? account(String? id) => id == null ? null : accounts[id];
  Json? category(String? id) => id == null ? null : categories[id];

  /// Returns [row] with its related documents embedded.
  ///
  /// A reference that resolves to nothing is left absent rather than attached as an
  /// empty map: the models treat a missing relation as "not loaded" and fall back to
  /// a readable placeholder, which is the right reading when a category was deleted
  /// out from under a historical transaction.
  Json attach(
    Json row, {
    String accountIdKey = 'account_id',
    String categoryIdKey = 'category_id',
    String? toAccountIdKey,
  }) {
    final accountJson = account(row.strOrNull(accountIdKey));
    final categoryJson = category(row.strOrNull(categoryIdKey));
    final toAccountJson =
        toAccountIdKey == null ? null : account(row.strOrNull(toAccountIdKey));

    if (accountJson == null && categoryJson == null && toAccountJson == null) {
      return row;
    }

    return <String, dynamic>{
      ...row,
      if (accountJson != null) 'account': accountJson,
      if (categoryJson != null) 'category': categoryJson,
      if (toAccountJson != null) 'to_account': toAccountJson,
    };
  }

  List<Json> attachAll(
    Iterable<Json> rows, {
    String accountIdKey = 'account_id',
    String categoryIdKey = 'category_id',
    String? toAccountIdKey,
  }) =>
      rows
          .map((row) => attach(
                row,
                accountIdKey: accountIdKey,
                categoryIdKey: categoryIdKey,
                toAccountIdKey: toAccountIdKey,
              ))
          .toList(growable: false);
}
