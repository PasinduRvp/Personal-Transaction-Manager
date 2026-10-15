// `Transaction` is Firestore's name for an atomic read-modify-write as well as
// this app's name for a financial record. The app's meaning wins here.
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:collection/collection.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/enums.dart';
import '../../core/errors/app_exception.dart';
import '../../core/services/firebase_service.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/money.dart';
import '../models/json_map.dart';
import '../models/transaction.dart';
import '../models/transaction_candidate.dart';
import '../models/budget.dart';
import '../models/transaction_query.dart';
import 'base_repository.dart';
import 'ledger_writer.dart';
import 'relation_loader.dart';

/// An opaque position in a paged result.
///
/// Firestore pages with a cursor rather than an offset, and that is the better
/// arrangement anyway: `range(2000, 2019)` in Postgres still scanned the first
/// two thousand rows, while a cursor starts exactly where the last page stopped.
/// The snapshot is wrapped so the UI layer passes a position around without
/// importing Firestore.
class TransactionCursor {
  const TransactionCursor(this.snapshot);

  final DocumentSnapshot<Map<String, dynamic>> snapshot;
}

/// One page of results, with the position to resume from.
class TransactionPage {
  const TransactionPage({
    required this.items,
    this.cursor,
    this.hasMore = false,
  });

  const TransactionPage.empty()
      : items = const [],
        cursor = null,
        hasMore = false;

  final List<Transaction> items;
  final TransactionCursor? cursor;
  final bool hasMore;
}

/// Transactions, at `users/{uid}/transactions`, with splits in a `splits`
/// subcollection under each.
///
/// Two things about this collection are worth stating up front.
///
/// **Balances are not written here.** A transaction is a single document, so the
/// client may create it directly, but the account balance it affects is updated
/// by the `onTransactionWritten` trigger with `FieldValue.increment`. That makes
/// concurrent posts from two devices add up instead of overwriting each other,
/// and it means a tampered client cannot invent a balance.
///
/// **Not every filter can run on the server.** Firestore cannot `OR` across
/// fields, cannot do substring matching, and restricts how range filters combine
/// with sorting. So the query is split: whatever Firestore can index is sent to
/// it, and the remainder is applied to the documents that come back, fetching
/// further pages until the requested count is filled. The division is explicit in
/// [_ServerPlan] rather than hidden, because it is the difference between a cheap
/// query and an expensive one.
class TransactionRepository extends BaseRepository {
  TransactionRepository({super.firestore});

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseService.transactions(userId);

  /// Ceiling on documents read while filling one page.
  ///
  /// Without it, a filter that matches nothing would walk the user's entire
  /// history — and bill for it — to return an empty list.
  static const int _scanLimit = 600;

  /// Ceiling on documents materialised when the sort cannot run on the server.
  static const int _materialiseLimit = 2000;

  // -------------------------------------------------------------------------
  // Reading
  // -------------------------------------------------------------------------

  /// One page of transactions matching [query], resuming after [after].
  Future<TransactionPage> fetchPage({
    required TransactionQuery query,
    TransactionCursor? after,
    int pageSize = AppConstants.transactionPageSize,
  }) =>
      guard(() async {
        final plan = _ServerPlan.from(query);

        if (!plan.canSortOnServer) {
          return _pageFromMaterialised(
            query: query,
            plan: plan,
            after: after,
            pageSize: pageSize,
          );
        }

        final index = await relations.load();
        final matched = <Transaction>[];
        DocumentSnapshot<Map<String, dynamic>>? cursor = after?.snapshot;
        var scanned = 0;
        var exhausted = false;

        // Each round trip reads a little more than the page size, because some of
        // what comes back may be filtered out here. Reading exactly `pageSize`
        // would mean a second round trip almost every time a filter is active.
        final batchSize = plan.needsClientFilter ? pageSize * 3 : pageSize;

        while (matched.length < pageSize && scanned < _scanLimit) {
          var q = plan.apply(_col, query.sort).limit(batchSize);
          if (cursor != null) q = q.startAfterDocument(cursor);

          final snapshot = await q.get();
          if (snapshot.docs.isEmpty) {
            exhausted = true;
            break;
          }

          scanned += snapshot.docs.length;
          cursor = snapshot.docs.last;

          for (final doc in snapshot.docs) {
            final transaction = Transaction.fromJson(index.attach(
              doc.asJson,
              toAccountIdKey: 'transfer_peer_account_id',
            ));
            if (plan.matches(transaction, query)) {
              matched.add(transaction);
              if (matched.length == pageSize) break;
            }
          }

          if (snapshot.docs.length < batchSize) {
            exhausted = true;
            break;
          }
        }

        return TransactionPage(
          items: matched,
          cursor: cursor == null ? null : TransactionCursor(cursor),
          hasMore: !exhausted && matched.length >= pageSize,
        );
      });

  /// The dashboard's recent list.
  Future<List<Transaction>> fetchRecent({int limit = 10}) => guard(() async {
        final snapshot = await _col
            .orderBy('transaction_date', descending: true)
            .orderBy(FieldPath.documentId, descending: true)
            .limit(limit)
            .get();

        final index = await relations.load();
        return _map(snapshot.docs.map((doc) => doc.asJson), index);
      });

  /// A single transaction, with its splits.
  Future<Transaction> fetchById(String id) => guard(() async {
        final snapshot = await _col.doc(id).get();
        if (!snapshot.exists) throw const NotFoundException();

        final index = await relations.load();
        final splits = await fetchSplits(id);

        return Transaction.fromJson(index.attach(
          snapshot.asJson,
          toAccountIdKey: 'transfer_peer_account_id',
        )).copyWith(splits: splits);
      });

  /// Both legs of a transfer.
  Future<List<Transaction>> fetchTransferGroup(String groupId) =>
      guard(() async {
        final snapshot = await _col
            .where('transfer_group_id', isEqualTo: groupId)
            .orderBy('transfer_direction')
            .get();
        final index = await relations.load();
        return _map(snapshot.docs.map((doc) => doc.asJson), index);
      });

  /// Transactions in a date range, for reports and CSV export.
  ///
  /// Not paged: the caller wants the whole window at once to total it or write it
  /// to a file. [limit] is a guard against a range that spans everything.
  Future<List<Transaction>> fetchRange({
    required DateRange range,
    TransactionQuery? query,
    int limit = 5000,
  }) =>
      guard(() async {
        final snapshot = await _col
            .where(
              'transaction_date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(range.start),
              isLessThanOrEqualTo: Timestamp.fromDate(range.end),
            )
            .orderBy('transaction_date', descending: true)
            .limit(limit)
            .get();

        final index = await relations.load();
        final all = _map(snapshot.docs.map((doc) => doc.asJson), index);
        if (query == null) return all;

        final plan = _ServerPlan.from(query);
        return all
            .where((t) => plan.matches(t, query, skipDateRange: true))
            .toList(growable: false);
      });

  /// How many transactions match [query].
  ///
  /// Exact when every facet of the query can be expressed as a Firestore filter.
  /// When it cannot, the count is of what the server could narrow to, and so an
  /// upper bound — the alternative is reading every matching document to count
  /// them, which is not worth a number in a subtitle. [TransactionCountResult]
  /// says which it is so the UI need not guess.
  Future<TransactionCountResult> countMatching(TransactionQuery query) =>
      guard(() async {
        final plan = _ServerPlan.from(query);
        final total = await countOf(plan.apply(_col, query.sort));
        return TransactionCountResult(
          count: total,
          isExact: !plan.needsClientFilter,
        );
      });

  /// Transactions attached to a document, so the review screen can show what a
  /// previous import produced.
  Future<List<Transaction>> fetchByDocument(String documentId) =>
      guard(() async {
        final snapshot = await _col
            .where('document_id', isEqualTo: documentId)
            .orderBy('transaction_date', descending: true)
            .get();
        final index = await relations.load();
        return _map(snapshot.docs.map((doc) => doc.asJson), index);
      });

  /// Streams the user's most recent transactions.
  ///
  /// The security rules confine the listener to this user's subcollection, so it
  /// cannot deliver anyone else's documents. Used on the dashboard so a
  /// transaction added on another device appears without a manual refresh.
  Stream<List<Transaction>> watchRecent({int limit = 10}) => _col
      .orderBy('transaction_date', descending: true)
      .limit(limit)
      .snapshots()
      .asyncMap((snapshot) async {
        final index = await relations.load();
        return _map(snapshot.docs.map((doc) => doc.asJson), index);
      });

  // -------------------------------------------------------------------------
  // Writing
  // -------------------------------------------------------------------------

  /// Creates a transaction, and moves everything derived from it in the same
  /// Firestore transaction.
  ///
  /// The balance, the month's rollup and any affected budget all change with the
  /// document or none of them do. There is no server here to do it afterwards, and
  /// a second write that could fail on its own would be worse than no separation at
  /// all — a balance that silently disagrees with the ledger is the one failure a
  /// finance app must not have.
  Future<Transaction> create(Transaction transaction) => guard(() async {
        if (transaction.type.isTransfer) {
          throw const ValidationException(
            'Use createTransfer to record a transfer so both accounts stay in '
            'step.',
          );
        }
        if (transaction.amount.isZero || transaction.amount.isNegative) {
          throw const ValidationException(
            'The amount must be greater than zero.',
          );
        }

        // Read before the Firestore transaction: the client SDK can only `get` a
        // document inside one, never run a query.
        final budgets = await _activeBudgets();
        final ref = _col.doc();

        await db.runTransaction((tx) async {
          tx.set(ref, {
            ...transaction.toInsertJson(),
            'user_id': userId,
            ...createdFields(),
          });

          LedgerWriter.apply(
            tx,
            userId: userId,
            before: null,
            after: LedgerWriter.effectOfModel(transaction),
            budgets: budgets,
          );
        });

        return fetchById(ref.id);
      });

  /// Edits a transaction, correcting every derived figure by the difference.
  ///
  /// The previous state is read inside the Firestore transaction rather than taken
  /// from the model the caller holds, so the correction is measured against what is
  /// actually stored. A stale model would otherwise make the balance drift by the
  /// difference between the two.
  Future<Transaction> update(Transaction transaction) => guard(() async {
        if (transaction.amount.isZero || transaction.amount.isNegative) {
          throw const ValidationException(
            'The amount must be greater than zero.',
          );
        }

        // A transfer's two legs must change together, so editing one directly is
        // not allowed.
        if (transaction.type.isTransfer) {
          return _updateTransfer(transaction);
        }

        final budgets = await _activeBudgets();
        final ref = _col.doc(transaction.id);

        await db.runTransaction((tx) async {
          final snapshot = await tx.get(ref);
          if (!snapshot.exists) throw const NotFoundException();

          final before = LedgerWriter.effectOf(snapshot.asJson);

          tx.update(ref, {
            ...transaction.toUpdateJson(),
            ...updatedFields(),
          });

          LedgerWriter.apply(
            tx,
            userId: userId,
            before: before,
            after: LedgerWriter.effectOfModel(transaction),
            budgets: budgets,
          );
        });

        return fetchById(transaction.id);
      });

  /// Deletes a transaction, or both legs when it is a transfer, reversing its
  /// effect on every derived figure.
  Future<void> delete(Transaction transaction) => guard(() async {
        if (transaction.type.isTransfer &&
            transaction.transferGroupId != null) {
          return _deleteTransfer(transaction.transferGroupId!);
        }

        // Splits live under the transaction and Firestore does not cascade, so
        // they would otherwise survive as documents nothing can reach. Deleted
        // first: if this fails the transaction still exists, which is recoverable,
        // whereas orphaned splits are not reachable to clean up.
        await _deleteSplits(transaction.id);

        final budgets = await _activeBudgets();
        final ref = _col.doc(transaction.id);

        await db.runTransaction((tx) async {
          final snapshot = await tx.get(ref);
          if (!snapshot.exists) return;

          final before = LedgerWriter.effectOf(snapshot.asJson);

          tx.delete(ref);

          LedgerWriter.apply(
            tx,
            userId: userId,
            before: before,
            after: null,
            budgets: budgets,
          );
        });
      });

  /// Copies a transaction onto today's date, for a purchase the user makes often.
  /// The copy is never a transfer and carries no attachment: the receipt belongs
  /// to the original.
  Future<Transaction> duplicate(Transaction source) => guard(() async {
        if (source.type.isTransfer) {
          throw const ValidationException(
            'Transfers cannot be duplicated. Create a new transfer instead.',
          );
        }
        final copy = Transaction(
          id: '',
          userId: userId,
          accountId: source.accountId,
          categoryId: source.categoryId,
          type: source.type,
          amount: source.amount,
          description: source.description,
          merchant: source.merchant,
          paymentMethod: source.paymentMethod,
          transactionDate: DateTime.now(),
          notes: source.notes,
          source: TransactionSource.manual,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        return create(copy);
      });

  Future<Transaction> setStatus(String id, TransactionStatus status) =>
      guard(() async {
        await _col.doc(id).update({
          'status': status.wire,
          ...updatedFields(),
        });
        return fetchById(id);
      });

  /// Attaches or replaces a transaction's receipt.
  Future<Transaction> setDocument(String id, String? documentId) =>
      guard(() async {
        await _col.doc(id).update({
          'document_id': documentId ?? FieldValue.delete(),
          ...updatedFields(),
        });
        return fetchById(id);
      });

  // -------------------------------------------------------------------------
  // Transfers
  // -------------------------------------------------------------------------

  /// Creates both legs of a transfer, atomically.
  ///
  /// Writing one leg and not the other would destroy money: the sending account
  /// would be down the amount with nothing to show where it went. A Firestore
  /// transaction covers both documents and both balance increments, so there is no
  /// moment at which only one exists.
  ///
  /// Both legs share a `transfer_group_id`, and each names the other's account so a
  /// list row can render "to Savings" without a second read.
  Future<String> createTransfer({
    required String fromAccountId,
    required String toAccountId,
    required Money amount,
    required DateTime date,
    String? description,
    String? notes,
    PaymentMethod? paymentMethod,
    String? documentId,
    Money? fee,
  }) =>
      guard(() async {
        if (fromAccountId == toAccountId) {
          throw const ValidationException(
            'Choose two different accounts for a transfer.',
          );
        }
        if (amount.isZero || amount.isNegative) {
          throw const ValidationException(
            'The transfer amount must be greater than zero.',
          );
        }
        if (fee != null && fee.isNegative) {
          throw const ValidationException(
            'The transfer fee cannot be negative.',
          );
        }

        final hasFee = fee != null && !fee.isZero;

        // A bank's own cut of the transfer, charged on top of the amount moved —
        // it leaves the source account like any other expense, so it goes through
        // the same budgets/rollups the ledger writer already applies to one.
        // Read before the Firestore transaction for the same reason `create()`
        // reads its budgets first: the client SDK cannot run a query inside one.
        final feeBudgets = hasFee ? await _activeBudgets() : const <Budget>[];
        final feeCategoryId =
            hasFee ? await _feesAndChargesCategoryId() : null;

        final groupId = _col.doc().id;
        final outRef = _col.doc();
        final inRef = _col.doc();
        final feeRef = hasFee ? _col.doc() : null;

        await db.runTransaction((tx) async {
          final from =
              await tx.get(FirebaseService.accounts(userId).doc(fromAccountId));
          final to =
              await tx.get(FirebaseService.accounts(userId).doc(toAccountId));

          if (!from.exists || !to.exists) {
            throw const NotFoundException();
          }

          // Both legs carry the same figure, so a transfer between accounts in
          // different currencies would silently invent an exchange rate. Refused
          // instead: the user can record an expense and an income with the real
          // rate they were given.
          final fromCurrency =
              from.asJson.str('currency', fallback: amount.currency);
          final toCurrency =
              to.asJson.str('currency', fallback: amount.currency);

          if (fromCurrency != toCurrency) {
            throw const ValidationException(
              'Those accounts hold different currencies. Record this as an '
              'expense and an income so the rate you were given is the one saved.',
            );
          }

          for (final leg in [
            (ref: outRef, direction: TransferDirection.out, account: fromAccountId, peer: toAccountId),
            (ref: inRef, direction: TransferDirection.incoming, account: toAccountId, peer: fromAccountId),
          ]) {
            tx.set(leg.ref, {
              'user_id': userId,
              'account_id': leg.account,
              // A transfer has no category: it is not spending, and putting it in
              // one would make it appear in a breakdown as money the user no longer
              // has.
              'category_id': null,
              'type': TransactionType.transfer.wire,
              ...moneyFields('amount', amount),
              'description': description,
              'merchant': null,
              'payment_method': paymentMethod?.wire,
              'transaction_date': Timestamp.fromDate(date),
              'notes': notes,
              'document_id': documentId,
              'source': TransactionSource.manual.wire,
              'status': TransactionStatus.confirmed.wire,
              'transfer_group_id': groupId,
              'transfer_direction': leg.direction.wire,
              'transfer_peer_account_id': leg.peer,
              'reference_number': null,
              'is_split': false,
              'search_terms': searchTerms([description, notes]),
              ...createdFields(),
            });

            // Transfers move no money in or out overall, so they touch balances but
            // never the rollups or a budget. The ledger writer applies that rule
            // itself; the increments below are the balance half of it.
            tx.update(FirebaseService.accounts(userId).doc(leg.account), {
              minorKey('current_balance'): FieldValue.increment(
                leg.direction == TransferDirection.incoming
                    ? amount.minorUnits
                    : -amount.minorUnits,
              ),
              ...updatedFields(),
            });
          }

          if (feeRef != null) {
            tx.set(feeRef, {
              'user_id': userId,
              'account_id': fromAccountId,
              'category_id': feeCategoryId,
              'type': TransactionType.expense.wire,
              ...moneyFields('amount', fee!),
              'description': 'Transfer fee',
              'merchant': null,
              'payment_method': paymentMethod?.wire,
              'transaction_date': Timestamp.fromDate(date),
              'notes': notes,
              'document_id': null,
              'source': TransactionSource.manual.wire,
              'status': TransactionStatus.confirmed.wire,
              'transfer_group_id': groupId,
              'reference_number': null,
              'is_split': false,
              'search_terms': searchTerms(['Transfer fee']),
              ...createdFields(),
            });

            // A real expense, unlike the two legs above: it belongs in the
            // rollups and any matching budget, so it goes through the same
            // ledger path `create()` uses rather than a bare balance increment.
            LedgerWriter.apply(
              tx,
              userId: userId,
              before: null,
              after: LedgerEffect(
                accountId: fromAccountId,
                categoryId: feeCategoryId,
                type: TransactionType.expense,
                status: TransactionStatus.confirmed,
                currency: fee.currency,
                amountMinor: fee.minorUnits.abs(),
                date: date,
                merchant: null,
                paymentMethod: paymentMethod?.wire,
                transferDirection: null,
              ),
              budgets: feeBudgets,
            );
          }
        });

        return groupId;
      });

  /// The id of the "Fees & Charges" default category, if it still exists under
  /// that name.
  ///
  /// Best-effort: a transfer fee is still worth recording as an expense even
  /// when the user renamed or deleted the category it would normally land in,
  /// so a miss here falls back to no category rather than failing the transfer.
  Future<String?> _feesAndChargesCategoryId() async {
    final index = await relations.load();
    for (final entry in index.categories.entries) {
      if (entry.value.str('name').trim().toLowerCase() ==
          'fees & charges') {
        return entry.key;
      }
    }
    return null;
  }

  /// Edits both legs together: the amount, the date and the description.
  ///
  /// Changing which accounts are involved is not an edit but a different transfer,
  /// and is done by deleting and recreating — which keeps the balance arithmetic in
  /// one place rather than spreading a four-way correction across this method.
  Future<Transaction> _updateTransfer(Transaction transaction) async {
    final groupId = transaction.transferGroupId;
    if (groupId == null) {
      throw const ValidationException(
        'This transfer is missing its link and cannot be edited.',
      );
    }

    final legs =
        await _col.where('transfer_group_id', isEqualTo: groupId).get();

    // A fee leg may share this group id but is a real expense, independent of
    // the amount being edited here — it is left untouched rather than scaled
    // along with the transfer.
    final transferLegs = legs.docs
        .where((doc) =>
            TransactionType.fromWire(doc.asJson.str('type')) ==
            TransactionType.transfer)
        .toList(growable: false);

    if (transferLegs.length != 2) {
      throw const ValidationException(
        'This transfer is missing one of its halves and cannot be edited.',
      );
    }

    await db.runTransaction((tx) async {
      for (final leg in transferLegs) {
        final before = LedgerWriter.effectOf(leg.asJson);
        if (before == null) continue;

        tx.update(leg.reference, {
          ...moneyFields('amount', transaction.amount),
          'transaction_date': Timestamp.fromDate(transaction.transactionDate),
          'description': transaction.description,
          'notes': transaction.notes,
          'payment_method': transaction.paymentMethod?.wire,
          'search_terms':
              searchTerms([transaction.description, transaction.notes]),
          ...updatedFields(),
        });

        // Only the balance moves: the amount changed, so the difference has to be
        // applied to the account this leg belongs to.
        final wasIncoming =
            before.transferDirection == TransferDirection.incoming;
        final previous =
            wasIncoming ? before.amountMinor : -before.amountMinor;
        final next = wasIncoming
            ? transaction.amount.minorUnits
            : -transaction.amount.minorUnits;

        if (next != previous) {
          tx.update(FirebaseService.accounts(userId).doc(before.accountId), {
            minorKey('current_balance'): FieldValue.increment(next - previous),
            ...updatedFields(),
          });
        }
      }
    });

    return fetchById(transaction.id);
  }

  /// Deletes every leg — both transfer halves, and the fee leg if one was
  /// recorded — reversing each one's effect.
  ///
  /// One at a time would leave a moment — or, if the connection dropped, forever —
  /// in which money had arrived somewhere it never left.
  Future<void> _deleteTransfer(String groupId) async {
    final legs =
        await _col.where('transfer_group_id', isEqualTo: groupId).get();

    if (legs.docs.isEmpty) throw const NotFoundException();

    // The fee leg is a real expense and needs its rollup/budget contribution
    // reversed too, not just its balance — which means its budgets have to be
    // read before the Firestore transaction, same as everywhere else.
    final hasFeeLeg = legs.docs.any((doc) =>
        TransactionType.fromWire(doc.asJson.str('type')) !=
        TransactionType.transfer);
    final budgets = hasFeeLeg ? await _activeBudgets() : const <Budget>[];

    await db.runTransaction((tx) async {
      for (final leg in legs.docs) {
        final before = LedgerWriter.effectOf(leg.asJson);
        tx.delete(leg.reference);

        if (before == null) continue;

        if (before.type.isTransfer) {
          if (!before.counts) continue;
          tx.update(FirebaseService.accounts(userId).doc(before.accountId), {
            minorKey('current_balance'):
                FieldValue.increment(-before.signedMinor),
            ...updatedFields(),
          });
        } else {
          LedgerWriter.apply(
            tx,
            userId: userId,
            before: before,
            after: null,
            budgets: budgets,
          );
        }
      }
    });
  }

  Future<void> _deleteSplits(String transactionId) async {
    final splits =
        await _col.doc(transactionId).collection(Paths.splits).get();
    if (splits.docs.isEmpty) return;

    final batch = db.batch();
    for (final doc in splits.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  /// Budgets that a transaction could affect.
  ///
  /// Read before any Firestore transaction, because the client SDK cannot run a
  /// query inside one. Firestore serves this from its local cache most of the time,
  /// so it is rarely a billed read.
  Future<List<Budget>> _activeBudgets() async {
    final snapshot = await FirebaseService.budgets(userId).get();

    return snapshot.docs
        .map((doc) => Budget.fromJson(doc.asJson))
        .where((b) => !b.isArchived)
        .toList(growable: false);
  }

  // -------------------------------------------------------------------------
  // Splits
  // -------------------------------------------------------------------------

  /// Replaces a transaction's split lines.
  ///
  /// The whole set is rewritten rather than diffed: working out which lines moved
  /// would be more code than rewriting at most a handful of documents, and the
  /// rewrite is one Firestore transaction so the set is never half-replaced.
  ///
  /// **The sum is checked here, and here only.** Postgres enforced "the splits add
  /// up to the transaction total" with a deferred constraint, and the paid plan
  /// enforced it in the one Cloud Function allowed to write these documents. On the
  /// free plan neither exists: Firestore rules cannot compare a set of documents
  /// against a field on their parent. So this check is the invariant, and it is
  /// only as strong as the client running it — which for a personal ledger means
  /// the only person who can break it is the one it belongs to.
  Future<void> replaceSplits({
    required Transaction transaction,
    required List<TransactionSplit> splits,
  }) =>
      guard(() async {
        if (splits.isNotEmpty) {
          final total = splits.map((s) => s.amount).reduce((a, b) => a + b);
          if (total != transaction.amount) {
            final difference = transaction.amount - total;
            throw ValidationException(
              difference.isPositive
                  ? 'The splits are ${difference.format()} short of the '
                      '${transaction.amount.format()} total.'
                  : 'The splits exceed the total by '
                      '${difference.abs.format()}.',
            );
          }

          final mismatched = splits.firstWhereOrNull(
            (s) => s.amount.currency != transaction.amount.currency,
          );
          if (mismatched != null) {
            throw const ValidationException(
              'Every split must be in the same currency as the transaction.',
            );
          }
        }

        final collection = FirebaseService.splits(transaction.id, userId);

        // Read outside the Firestore transaction: the client SDK cannot query
        // inside one, and these are only needed to know what to remove.
        final existing = await collection.get();

        await db.runTransaction((tx) async {
          final parent = await tx.get(_col.doc(transaction.id));
          if (!parent.exists) throw const NotFoundException();

          for (final doc in existing.docs) {
            tx.delete(doc.reference);
          }

          for (var index = 0; index < splits.length; index++) {
            tx.set(collection.doc(), {
              ...splits[index].toInsertJson(transaction.id),
              'user_id': userId,
              'sort_order': index,
              ...createdFields(),
            });
          }

          // The flag lives on the transaction so a list row can show a split marker
          // without reading the subcollection for every row on screen.
          tx.update(_col.doc(transaction.id), {
            'is_split': splits.isNotEmpty,
            ...updatedFields(),
          });
        });
      });

  Future<List<TransactionSplit>> fetchSplits(String transactionId) =>
      guard(() async {
        final snapshot = await FirebaseService.splits(transactionId, userId)
            .orderBy('sort_order')
            .get();
        if (snapshot.docs.isEmpty) return const <TransactionSplit>[];

        final index = await relations.load();
        return snapshot.docs
            .map((doc) => TransactionSplit.fromJson(index.attach(doc.asJson)))
            .toList(growable: false);
      });

  // -------------------------------------------------------------------------
  // Duplicate detection
  // -------------------------------------------------------------------------

  /// Looks for existing transactions that resemble the one being created.
  ///
  /// Advisory only. The caller shows the matches and lets the user skip, create
  /// anyway, or open the existing transaction — nothing is merged or deleted
  /// automatically.
  ///
  /// Scored by a callable rather than on the client: the comparison window spans
  /// several days around the date, and reading that window to the device on every
  /// keystroke of a form would be both slow and billable.
  Future<List<DuplicateMatch>> findDuplicates({
    required Money amount,
    required DateTime date,
    String? merchant,
    String? accountId,
    String? reference,
    String? excludeTransactionId,
    int toleranceDays = AppConstants.duplicateDateToleranceDays,
  }) =>
      guard(() async {
        final tolerance = toleranceDays.clamp(0, 30);
        final from = AppDateUtils.startOfDay(
          date.subtract(Duration(days: tolerance)),
        );
        final to = AppDateUtils.endOfDay(date.add(Duration(days: tolerance)));

        // The same amount is required rather than scored: two transactions for
        // different amounts are not the same transaction, whatever else they have
        // in common. That also keeps this to one indexed query over a few documents
        // rather than a scan of the period.
        final snapshot = await _col
            .where(minorKey('amount'), isEqualTo: amount.minorUnits.abs())
            .where(
              'transaction_date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(from),
              isLessThanOrEqualTo: Timestamp.fromDate(to),
            )
            .limit(50)
            .get();

        if (snapshot.docs.isEmpty) return const <DuplicateMatch>[];

        final index = await relations.load();
        final matches = <DuplicateMatch>[];

        for (final doc in snapshot.docs) {
          if (doc.id == excludeTransactionId) continue;

          final json = doc.asJson;
          final reasons = <String>[];
          var score = 0.0;

          // An exact reference match is the strongest signal a statement can give.
          final existingReference = json.strOrNull('reference_number');
          if (reference != null &&
              existingReference != null &&
              existingReference.trim().toUpperCase() ==
                  reference.trim().toUpperCase()) {
            score += 0.60;
            reasons.add('Same reference');
          }

          // Always true given the query above, but scored and named explicitly so
          // the reasons shown to the user are complete.
          score += 0.25;
          reasons.add('Same amount');

          final existingDate = json.dateOrNull('transaction_date');
          if (existingDate != null) {
            if (AppDateUtils.isSameDay(existingDate, date)) {
              score += 0.10;
              reasons.add('Same date');
            } else {
              score += 0.05;
              reasons.add('Nearby date');
            }
          }

          if (accountId != null && json.strOrNull('account_id') == accountId) {
            score += 0.05;
            reasons.add('Same account');
          }

          final existingMerchant = json.strOrNull('merchant');
          if (merchant != null &&
              existingMerchant != null &&
              _similarity(
                    existingMerchant.toLowerCase(),
                    merchant.toLowerCase(),
                  ) >
                  0.55) {
            score += 0.15;
            reasons.add('Similar merchant');
          }

          // Amount plus a nearby date already scores 0.30; below that is noise.
          if (score < 0.30) continue;

          matches.add(DuplicateMatch(
            existing: Transaction.fromJson(index.attach(
              json,
              toAccountIdKey: 'transfer_peer_account_id',
            )),
            score: score > 1 ? 1 : double.parse(score.toStringAsFixed(4)),
            reasons: reasons,
          ));
        }

        matches.sort((a, b) {
          final byScore = b.score.compareTo(a.score);
          return byScore != 0 ? byScore : a.existing.id.compareTo(b.existing.id);
        });

        return matches.take(10).toList(growable: false);
      });

  /// Dice coefficient over character bigrams, standing in for `pg_trgm`.
  ///
  /// Postgres had trigram similarity, so "Keells Super" and "KEELS SUPER" scored as
  /// the same merchant. There is no equivalent here, so the same idea is computed
  /// directly: `similarity('keells super', 'keels super')` is about 0.8, well over
  /// the 0.55 threshold, while two unrelated names score near zero.
  static double _similarity(String a, String b) {
    final left = a.trim();
    final right = b.trim();

    if (left == right) return 1;
    // A string of one character has no bigrams to compare.
    if (left.length < 2 || right.length < 2) return 0;

    Map<String, int> bigrams(String value) {
      final result = <String, int>{};
      for (var i = 0; i < value.length - 1; i++) {
        final gram = value.substring(i, i + 2);
        result[gram] = (result[gram] ?? 0) + 1;
      }
      return result;
    }

    final leftGrams = bigrams(left);
    final rightGrams = bigrams(right);

    var shared = 0;
    for (final entry in leftGrams.entries) {
      final other = rightGrams[entry.key];
      if (other != null) {
        shared += entry.value < other ? entry.value : other;
      }
    }

    final total = leftGrams.values.fold<int>(0, (a, b) => a + b) +
        rightGrams.values.fold<int>(0, (a, b) => a + b);

    return total == 0 ? 0 : (2 * shared) / total;
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  List<Transaction> _map(Iterable<Json> rows, RelationIndex index) => index
      .attachAll(rows, toAccountIdKey: 'transfer_peer_account_id')
      .map(Transaction.fromJson)
      .toList(growable: false);

  /// Pages a sort Firestore cannot perform.
  ///
  /// Sorting by amount or merchant while filtering a date range would need the
  /// range field to lead the ordering, which contradicts the requested sort. So a
  /// bounded window is read, sorted here, and handed out a page at a time.
  /// [_materialiseLimit] is the honest limit of that approach, and the UI's date
  /// filter is what keeps a user from meeting it.
  Future<TransactionPage> _pageFromMaterialised({
    required TransactionQuery query,
    required _ServerPlan plan,
    required TransactionCursor? after,
    required int pageSize,
  }) async {
    final snapshot = await plan
        .apply(_col, TransactionSort.newest)
        .limit(_materialiseLimit)
        .get();

    final index = await relations.load();
    final all = _map(snapshot.docs.map((doc) => doc.asJson), index)
        .where((t) => plan.matches(t, query))
        .toList()
      ..sort(_comparatorFor(query.sort));

    // The cursor for an in-memory page is the id of the last item handed out,
    // which is enough to find the position again in a list sorted the same way.
    final startId = after?.snapshot.id;
    final startIndex =
        startId == null ? 0 : all.indexWhere((t) => t.id == startId) + 1;

    if (startIndex <= 0 && startId != null) {
      // The anchor is gone — deleted, or filtered out by an edit. Starting over
      // is better than silently returning nothing.
      return TransactionPage(items: all.take(pageSize).toList(), hasMore: all.length > pageSize);
    }

    final slice = all.skip(startIndex).take(pageSize).toList(growable: false);
    final lastId = slice.isEmpty ? null : slice.last.id;

    return TransactionPage(
      items: slice,
      cursor: lastId == null
          ? null
          : TransactionCursor(snapshot.docs.firstWhere(
              (doc) => doc.id == lastId,
              orElse: () => snapshot.docs.last,
            )),
      hasMore: startIndex + slice.length < all.length,
    );
  }

  static int Function(Transaction, Transaction) _comparatorFor(
    TransactionSort sort,
  ) =>
      switch (sort) {
        TransactionSort.newest => (a, b) =>
            b.transactionDate.compareTo(a.transactionDate),
        TransactionSort.oldest => (a, b) =>
            a.transactionDate.compareTo(b.transactionDate),
        TransactionSort.amountHigh => (a, b) =>
            b.amount.minorUnits.compareTo(a.amount.minorUnits),
        TransactionSort.amountLow => (a, b) =>
            a.amount.minorUnits.compareTo(b.amount.minorUnits),
        TransactionSort.merchantAsc => (a, b) => (a.merchant ?? '')
            .toLowerCase()
            .compareTo((b.merchant ?? '').toLowerCase()),
        TransactionSort.merchantDesc => (a, b) => (b.merchant ?? '')
            .toLowerCase()
            .compareTo((a.merchant ?? '').toLowerCase()),
      };
}

/// The result of counting a filtered query.
class TransactionCountResult {
  const TransactionCountResult({required this.count, required this.isExact});

  final int count;

  /// False when filters had to be applied on the client, making [count] an upper
  /// bound rather than the number of rows the user will see.
  final bool isExact;
}

/// Splits a [TransactionQuery] into the part Firestore can index and the part
/// that has to be checked on the client.
///
/// Firestore's limits that force the split:
///
///   * no `OR` across different fields, so free-text search over four columns
///     becomes one `array-contains` against the stored `search_terms`;
///   * one `whereIn` per query, so only the most selective set filter is sent;
///   * a range filter must lead the ordering, so an amount range cannot be
///     combined with a date sort server-side.
class _ServerPlan {
  _ServerPlan._({
    required this.searchTerm,
    required this.extraSearchTerms,
    required this.serverSet,
    required this.dateRange,
    required this.clientFilters,
    required this.canSortOnServer,
  });

  /// The one token sent to Firestore; the rest are matched here.
  final String? searchTerm;
  final List<String> extraSearchTerms;

  /// The single `whereIn` this query gets to use, as (field, values).
  final (String, List<String>)? serverSet;
  final DateRange? dateRange;

  /// Which facets could not be sent and so are checked on each document.
  final Set<_ClientFilter> clientFilters;
  final bool canSortOnServer;

  bool get needsClientFilter =>
      clientFilters.isNotEmpty || extraSearchTerms.isNotEmpty;

  static _ServerPlan from(TransactionQuery query) {
    final terms = query.hasSearch
        ? searchQueryTerms(query.search!)
        : const <String>[];
    final clientFilters = <_ClientFilter>{};

    // Exactly one `whereIn` is allowed, so the most selective set wins and the
    // others are checked per document. Accounts and categories are the ones users
    // filter by most, and are usually the narrowest.
    (String, List<String>)? serverSet;
    if (query.categoryIds.isNotEmpty && query.categoryIds.length <= 30) {
      serverSet = ('category_id', query.categoryIds.toList());
    } else if (query.accountIds.isNotEmpty && query.accountIds.length <= 30) {
      serverSet = ('account_id', query.accountIds.toList());
    } else if (query.types.isNotEmpty && query.types.length <= 30) {
      serverSet = ('type', query.types.map((t) => t.wire).toList());
    }

    if (query.categoryIds.isNotEmpty && serverSet?.$1 != 'category_id') {
      clientFilters.add(_ClientFilter.categories);
    }
    if (query.accountIds.isNotEmpty && serverSet?.$1 != 'account_id') {
      clientFilters.add(_ClientFilter.accounts);
    }
    if (query.types.isNotEmpty && serverSet?.$1 != 'type') {
      clientFilters.add(_ClientFilter.types);
    }
    if (query.types.isEmpty && !query.includeTransfers) {
      clientFilters.add(_ClientFilter.transfers);
    }
    if (query.paymentMethods.isNotEmpty) {
      clientFilters.add(_ClientFilter.paymentMethods);
    }
    if (query.sources.isNotEmpty) clientFilters.add(_ClientFilter.sources);
    if (query.statuses.isNotEmpty) clientFilters.add(_ClientFilter.statuses);
    if (query.minAmount != null || query.maxAmount != null) {
      clientFilters.add(_ClientFilter.amount);
    }
    if (query.onlyWithAttachments) {
      clientFilters.add(_ClientFilter.attachments);
    }

    final sortsByDate = query.sort == TransactionSort.newest ||
        query.sort == TransactionSort.oldest;

    return _ServerPlan._(
      searchTerm: terms.isEmpty ? null : terms.first,
      extraSearchTerms: terms.skip(1).toList(growable: false),
      serverSet: serverSet,
      dateRange: query.dateRange,
      clientFilters: clientFilters,
      canSortOnServer: sortsByDate,
    );
  }

  /// Builds the Firestore query.
  Query<Map<String, dynamic>> apply(
    CollectionReference<Map<String, dynamic>> collection,
    TransactionSort sort,
  ) {
    Query<Map<String, dynamic>> q = collection;

    if (searchTerm != null) {
      q = q.where('search_terms', arrayContains: searchTerm);
    }

    final set = serverSet;
    if (set != null) {
      q = set.$2.length == 1
          ? q.where(set.$1, isEqualTo: set.$2.single)
          : q.where(set.$1, whereIn: set.$2);
    }

    final range = dateRange;
    if (range != null) {
      q = q.where(
        'transaction_date',
        isGreaterThanOrEqualTo: Timestamp.fromDate(range.start),
        isLessThanOrEqualTo: Timestamp.fromDate(range.end),
      );
    }

    // The document id is the tie-breaker, so paging stays stable when several
    // transactions share a timestamp. Without it a document can appear on two
    // pages or on neither.
    final descending = sort != TransactionSort.oldest;
    return q
        .orderBy('transaction_date', descending: descending)
        .orderBy(FieldPath.documentId, descending: descending);
  }

  /// Checks the facets the server could not.
  bool matches(
    Transaction t,
    TransactionQuery query, {
    bool skipDateRange = false,
  }) {
    for (final term in extraSearchTerms) {
      if (!_hasTerm(t, term)) return false;
    }

    for (final filter in clientFilters) {
      final ok = switch (filter) {
        _ClientFilter.categories =>
          t.categoryId != null && query.categoryIds.contains(t.categoryId),
        _ClientFilter.accounts => query.accountIds.contains(t.accountId),
        _ClientFilter.types => query.types.contains(t.type),
        _ClientFilter.transfers => !t.type.isTransfer,
        _ClientFilter.paymentMethods => t.paymentMethod != null &&
            query.paymentMethods.contains(t.paymentMethod),
        _ClientFilter.sources => query.sources.contains(t.source),
        _ClientFilter.statuses => query.statuses.contains(t.status),
        _ClientFilter.amount => _withinAmount(t, query),
        _ClientFilter.attachments => t.documentId != null,
      };
      if (!ok) return false;
    }

    if (!skipDateRange && dateRange != null) {
      final range = dateRange!;
      if (t.transactionDate.isBefore(range.start) ||
          t.transactionDate.isAfter(range.end)) {
        return false;
      }
    }

    return true;
  }

  static bool _withinAmount(Transaction t, TransactionQuery query) {
    final min = query.minAmount;
    final max = query.maxAmount;
    if (min != null && t.amount.minorUnits < min.minorUnits) return false;
    if (max != null && t.amount.minorUnits > max.minorUnits) return false;
    return true;
  }

  static bool _hasTerm(Transaction t, String term) {
    bool contains(String? value) =>
        value != null && value.toLowerCase().contains(term);
    return contains(t.merchant) ||
        contains(t.description) ||
        contains(t.notes) ||
        contains(t.referenceNumber);
  }
}

enum _ClientFilter {
  categories,
  accounts,
  types,
  transfers,
  paymentMethods,
  sources,
  statuses,
  amount,
  attachments,
}
