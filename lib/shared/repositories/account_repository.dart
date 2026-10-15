import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/errors/app_exception.dart';
import '../../core/services/firebase_service.dart';
import '../../core/utils/money.dart';
import '../models/account.dart';
import '../models/json_map.dart';
import 'base_repository.dart';
import 'relation_loader.dart';

/// Accounts, at `users/{uid}/accounts`.
///
/// No cache layer: Firestore's own offline persistence keeps the last read copy
/// of this collection on the device and serves it when there is no connection,
/// which is what the hand-rolled cache in the Postgres build existed to do.
class AccountRepository extends BaseRepository {
  AccountRepository({super.firestore});

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseService.accounts(userId);

  /// All accounts, active first, then by the user's ordering.
  ///
  /// Three order clauses need a composite index; it is declared in
  /// `firestore.indexes.json` rather than left to the console's error link, so a
  /// fresh deploy works without a first-run failure.
  Future<List<Account>> fetchAll({bool includeArchived = false}) async {
    List<Account> accounts;
    try {
      accounts = await fetchList(
        _col
            .orderBy('is_archived')
            .orderBy('sort_order')
            .orderBy('created_at'),
        Account.fromJson,
      );
    } catch (_) {
      accounts = await fetchList(_col, Account.fromJson);
      accounts.sort((a, b) {
        final archivedCmp = (a.isArchived ? 1 : 0).compareTo(b.isArchived ? 1 : 0);
        if (archivedCmp != 0) return archivedCmp;
        final sortCmp = a.sortOrder.compareTo(b.sortOrder);
        if (sortCmp != 0) return sortCmp;
        return a.createdAt.compareTo(b.createdAt);
      });
    }
    if (includeArchived) return accounts;
    return accounts.where((a) => !a.isArchived).toList(growable: false);
  }

  /// Live accounts, for screens that should reflect a balance change the moment
  /// the Cloud Function applies it.
  Stream<List<Account>> watchAll({bool includeArchived = false}) {
    Stream<List<Account>> stream;
    try {
      stream = watchList(
        _col.orderBy('is_archived').orderBy('sort_order').orderBy('created_at'),
        Account.fromJson,
      );
    } catch (_) {
      stream = watchList(_col, Account.fromJson);
    }
    return stream.map((accounts) {
      final sorted = List<Account>.from(accounts)
        ..sort((a, b) {
          final archivedCmp = (a.isArchived ? 1 : 0).compareTo(b.isArchived ? 1 : 0);
          if (archivedCmp != 0) return archivedCmp;
          final sortCmp = a.sortOrder.compareTo(b.sortOrder);
          if (sortCmp != 0) return sortCmp;
          return a.createdAt.compareTo(b.createdAt);
        });
      return includeArchived
          ? sorted
          : sorted.where((a) => !a.isArchived).toList(growable: false);
    });
  }

  Future<Account> fetchById(String id) =>
      fetchDoc(_col.doc(id), Account.fromJson);

  /// Creates an account.
  ///
  /// `current_balance_minor` is written equal to the opening balance, and the
  /// security rules require exactly that on create. After creation only the
  /// Cloud Function that posts transactions may change it, so the balance on
  /// screen is always the sum of what was actually posted. Setting it here rather
  /// than in a trigger means the new account shows its opening balance
  /// immediately instead of flashing zero.
  Future<Account> create(Account account) => guard(() async {
        final ref = _col.doc();
        await ref.set({
          ...account.toInsertJson(),
          'user_id': userId,
          ...moneyFields(
            'current_balance',
            account.initialBalance,
            withCurrency: false,
          ),
          ...createdFields(),
        });
        RelationLoader.invalidate();
        return fetchById(ref.id);
      });

  Future<Account> update(Account account) => guard(() async {
        await _col.doc(account.id).update({
          ...account.toUpdateJson(),
          ...updatedFields(),
        });
        // Transaction lists show the account's name through the shared lookup, so a
        // rename has to drop it or the old name survives on screen.
        RelationLoader.invalidate();
        return fetchById(account.id);
      });

  /// Changes the opening balance, shifting the current balance by the same delta
  /// so the transactions already posted on top of it are preserved.
  ///
  /// This is the one place a client may touch `current_balance_minor`, and the
  /// rules allow it only when both fields move by an identical amount — which is
  /// checkable in a rule, so it needs no Cloud Function.
  Future<Account> updateInitialBalance(String id, Money balance) =>
      guard(() async {
        final account = await fetchById(id);
        if (account.initialBalance.currency != balance.currency) {
          throw const ValidationException(
            'The opening balance must be in the same currency as the account.',
          );
        }

        final delta = balance.minorUnits - account.initialBalance.minorUnits;
        if (delta == 0) return account;

        await _col.doc(id).update({
          minorKey('initial_balance'): balance.minorUnits,
          minorKey('current_balance'):
              account.currentBalance.minorUnits + delta,
          ...updatedFields(),
        });
        return fetchById(id);
      });

  Future<Account> setArchived(String id, {required bool archived}) =>
      guard(() async {
        await _col.doc(id).update({
          'is_archived': archived,
          'is_active': !archived,
          ...updatedFields(),
        });
        RelationLoader.invalidate();
        return fetchById(id);
      });

  /// Permanently deletes an account, but only when it holds no transactions.
  ///
  /// Firestore does not cascade, so deleting one that still has transactions
  /// would orphan them: they would keep counting in the analytics rollups while
  /// pointing at an account that no longer exists. Archiving is offered instead.
  Future<void> delete(String id, {bool force = false}) => guard(() async {
        final existing = await transactionCount(id);
        if (existing > 0 && !force) {
          throw ValidationException(
            'This account has $existing transaction'
            '${existing == 1 ? '' : 's'}. '
            'Archive it instead so your history stays intact.',
          );
        }
        await _col.doc(id).delete();
        RelationLoader.invalidate();
      });

  /// Number of transactions posted to an account.
  ///
  /// An aggregation query, so this costs a fraction of a read rather than one
  /// read per transaction.
  Future<int> transactionCount(String accountId) => countOf(
        FirebaseService.transactions(userId)
            .where('account_id', isEqualTo: accountId),
      );

  /// Persists a drag-to-reorder result.
  ///
  /// One batch, so the list cannot end up half-reordered if the write fails
  /// partway. A batch tops out at 500 operations, which no realistic account
  /// list approaches.
  Future<void> reorder(List<String> orderedIds) => guard(() async {
        final batch = db.batch();
        for (var index = 0; index < orderedIds.length; index++) {
          batch.update(_col.doc(orderedIds[index]), {
            'sort_order': index,
            ...updatedFields(),
          });
        }
        await batch.commit();
      });
}
