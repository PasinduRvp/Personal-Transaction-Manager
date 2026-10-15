import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/app_exception.dart';
import '../../core/services/firebase_service.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/money.dart';
import '../models/bill.dart';
import '../models/budget.dart';
import '../models/json_map.dart';
import '../models/subscription.dart';
import 'base_repository.dart';
import 'ledger_writer.dart';

/// Bills, at `users/{uid}/bills`.
///
/// Due dates are stored as `yyyy-MM-dd` strings rather than timestamps, so they
/// compare and sort lexicographically in a `where` clause and never shift a day
/// when the device changes time zone. A bill due on the 1st must not read as due
/// on the 31st because someone flew east.
class BillRepository extends BaseRepository {
  BillRepository({super.firestore});

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseService.bills(userId);

  Future<List<Bill>> fetchAll({bool includeArchived = false}) =>
      guard(() async {
        final query = includeArchived
            ? _col.orderBy('due_date')
            : _col.where('is_archived', isEqualTo: false).orderBy('due_date');

        final snapshot = await query.get();
        if (snapshot.docs.isEmpty) return const <Bill>[];

        final index = await relations.load();
        return index
            .attachAll(snapshot.docs.map((doc) => doc.asJson))
            .map(Bill.fromJson)
            .toList(growable: false);
      });

  /// Unpaid bills due within [days], for the dashboard's upcoming list.
  ///
  /// Overdue bills are included because a bill that slipped past its date is the
  /// most important thing this list can show, and `status` is advanced to
  /// `OVERDUE` by the scheduled function rather than inferred on the client.
  Future<List<Bill>> fetchUpcoming({int days = 30, int limit = 5}) =>
      guard(() async {
        final snapshot = await _col
            .where('is_archived', isEqualTo: false)
            .where('status', whereIn: [
              BillStatus.unpaid.wire,
              BillStatus.overdue.wire,
            ])
            .where(
              'due_date',
              isLessThanOrEqualTo:
                  DateDisplay.iso(DateTime.now().add(Duration(days: days))),
            )
            .orderBy('due_date')
            .limit(limit)
            .get();

        if (snapshot.docs.isEmpty) return const <Bill>[];

        final index = await relations.load();
        return index
            .attachAll(snapshot.docs.map((doc) => doc.asJson))
            .map(Bill.fromJson)
            .toList(growable: false);
      });

  Future<Bill> fetchById(String id) => guard(() async {
        final snapshot = await _col.doc(id).get();
        if (!snapshot.exists) throw const NotFoundException();
        final index = await relations.load();
        return Bill.fromJson(index.attach(snapshot.asJson));
      });

  Future<Bill> create(Bill bill) => guard(() async {
        final ref = _col.doc();
        await ref.set({
          ...bill.toInsertJson(),
          'user_id': userId,
          ...createdFields(),
        });
        return fetchById(ref.id);
      });

  Future<Bill> update(Bill bill) => guard(() async {
        await _col.doc(bill.id).update({
          ...bill.toUpdateJson(),
          ...updatedFields(),
        });
        return fetchById(bill.id);
      });

  Future<void> delete(String id) => guard(() => _col.doc(id).delete());

  Future<Bill> setArchived(String id, {required bool archived}) =>
      guard(() async {
        await _col.doc(id).update({
          'is_archived': archived,
          ...updatedFields(),
        });
        return fetchById(id);
      });

  /// Records payment of a bill.
  ///
  /// A callable, because paying a bill writes the expense transaction, marks the
  /// bill paid and advances a recurring bill to its next due date. Doing that
  /// from the client would risk a bill marked paid with no transaction behind it —
  /// the user's balance would then be wrong with nothing on screen to explain why.
  /// Returns the new transaction's id.
  Future<String> markPaid({
    required String billId,
    required String accountId,
    DateTime? paidOn,
    Money? amount,
  }) =>
      guard(() async {
        final when = paidOn ?? DateTime.now();

        // Read before the Firestore transaction: the client SDK cannot query inside
        // one, and the ledger writer needs the budgets that this expense may count
        // against.
        final budgets = await _activeBudgets();
        final transactionRef = FirebaseService.transactions(userId).doc();

        await db.runTransaction((tx) async {
          final bill = await tx.get(_col.doc(billId));
          final account =
              await tx.get(FirebaseService.accounts(userId).doc(accountId));

          if (!bill.exists) throw const NotFoundException();
          if (!account.exists) {
            throw const ValidationException('That account no longer exists.');
          }

          final data = bill.asJson;
          final status = BillStatus.fromWire(data.strOrNull('status'));

          if (status == BillStatus.paid) {
            throw const ValidationException(
              'This bill is already marked paid.',
            );
          }
          if (status == BillStatus.cancelled) {
            throw const ValidationException(
              'That bill was cancelled. Reopen it before recording a payment.',
            );
          }

          final due = data.money('amount');
          final payment = amount ?? due;

          if (payment.isZero || payment.isNegative) {
            throw const ValidationException(
              'This bill has no amount. Add one before recording a payment.',
            );
          }

          final accountCurrency =
              account.asJson.str('currency', fallback: payment.currency);
          if (accountCurrency != payment.currency) {
            throw ValidationException(
              'This bill is in ${payment.currency} and that account holds '
              '$accountCurrency. Choose a matching account.',
            );
          }

          final name = data.str('name', fallback: 'Bill');
          final payee = data.strOrNull('payee');

          // The expense and the bill's new status are written together. A bill
          // marked paid with no transaction behind it would leave the balance wrong
          // with nothing on screen to explain why.
          tx.set(transactionRef, {
            'user_id': userId,
            'account_id': accountId,
            'category_id': data.strOrNull('category_id'),
            'type': TransactionType.expense.wire,
            ...moneyFields('amount', payment),
            'description': '$name payment',
            'merchant': payee,
            'payment_method': data.strOrNull('payment_method'),
            'transaction_date': Timestamp.fromDate(when),
            'notes': null,
            'document_id': null,
            'source': TransactionSource.manual.wire,
            'status': TransactionStatus.confirmed.wire,
            'reference_number': data.strOrNull('reference_number'),
            'bill_id': billId,
            'is_split': false,
            'search_terms': searchTerms([name, payee], prefixed: [payee]),
            ...createdFields(),
          });

          // A recurring bill advances to its next due date and reopens; a one-off
          // bill simply closes. Advancing here rather than on a schedule means the
          // next instance is visible the moment this one is paid.
          //
          // `frequency` is absent on a one-off bill, which is what distinguishes
          // the two — `fromWire` defaults to monthly, so the raw value is checked
          // rather than the parsed one.
          final rawFrequency = data.strOrNull('frequency');
          final dueDate = data.dateOrNull('due_date') ?? when;
          final next = rawFrequency == null
              ? null
              : AppDateUtils.advance(
                  dueDate,
                  RecurrenceFrequency.fromWire(rawFrequency),
                );

          tx.update(_col.doc(billId), {
            'status': next == null
                ? BillStatus.paid.wire
                : BillStatus.unpaid.wire,
            'paid_transaction_id': transactionRef.id,
            'last_paid_on': dateOnly(when),
            if (next != null) 'due_date': dateOnly(next),
            ...updatedFields(),
          });

          LedgerWriter.apply(
            tx,
            userId: userId,
            before: null,
            after: LedgerEffect(
              accountId: accountId,
              categoryId: data.strOrNull('category_id'),
              type: TransactionType.expense,
              status: TransactionStatus.confirmed,
              currency: payment.currency,
              amountMinor: payment.minorUnits.abs(),
              date: when,
              merchant: payee,
              paymentMethod: data.strOrNull('payment_method'),
              transferDirection: null,
            ),
            budgets: budgets,
          );
        });

        return transactionRef.id;
      });

  Future<List<Budget>> _activeBudgets() async {
    final snapshot = await FirebaseService.budgets(userId).get();
    return snapshot.docs
        .map((doc) => Budget.fromJson(doc.asJson))
        .where((b) => !b.isArchived)
        .toList(growable: false);
  }
}

/// Subscriptions, at `users/{uid}/subscriptions`.
class SubscriptionRepository extends BaseRepository {
  SubscriptionRepository({super.firestore});

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseService.subscriptions(userId);

  Future<List<Subscription>> fetchAll({bool includeArchived = false}) =>
      guard(() async {
        final query = includeArchived
            ? _col
                .orderBy('is_active', descending: true)
                .orderBy('next_renewal_date')
            : _col
                .where('is_archived', isEqualTo: false)
                .orderBy('is_active', descending: true)
                .orderBy('next_renewal_date');

        final snapshot = await query.get();
        if (snapshot.docs.isEmpty) return const <Subscription>[];

        final index = await relations.load();
        return index
            .attachAll(snapshot.docs.map((doc) => doc.asJson))
            .map(Subscription.fromJson)
            .toList(growable: false);
      });

  Future<Subscription> fetchById(String id) => guard(() async {
        final snapshot = await _col.doc(id).get();
        if (!snapshot.exists) throw const NotFoundException();
        final index = await relations.load();
        return Subscription.fromJson(index.attach(snapshot.asJson));
      });

  Future<Subscription> create(Subscription subscription) => guard(() async {
        final ref = _col.doc();
        await ref.set({
          ...subscription.toInsertJson(),
          'user_id': userId,
          ...createdFields(),
        });
        return fetchById(ref.id);
      });

  Future<Subscription> update(Subscription subscription) => guard(() async {
        await _col.doc(subscription.id).update({
          ...subscription.toUpdateJson(),
          ...updatedFields(),
        });
        return fetchById(subscription.id);
      });

  Future<Subscription> setActive(String id, {required bool active}) =>
      guard(() async {
        await _col.doc(id).update({
          'is_active': active,
          ...updatedFields(),
        });
        return fetchById(id);
      });

  Future<void> delete(String id) => guard(() => _col.doc(id).delete());
}

/// Recurring transaction schedules, at `users/{uid}/recurringTransactions`.
///
/// The schedules are executed by the daily scheduled function, not by the app on
/// launch: a schedule should post whether or not anyone opened the app that day,
/// and two devices opening it would otherwise post the same month twice.
class RecurringRepository extends BaseRepository {
  RecurringRepository({super.firestore});

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseService.recurring(userId);

  Future<List<RecurringTransaction>> fetchAll({bool activeOnly = false}) =>
      guard(() async {
        final query = activeOnly
            ? _col
                .where('is_active', isEqualTo: true)
                .orderBy('next_execution_date')
            : _col
                .orderBy('is_active', descending: true)
                .orderBy('next_execution_date');

        final snapshot = await query.get();
        if (snapshot.docs.isEmpty) return const <RecurringTransaction>[];

        final index = await relations.load();
        return index
            .attachAll(snapshot.docs.map((doc) => doc.asJson))
            .map(RecurringTransaction.fromJson)
            .toList(growable: false);
      });

  Future<RecurringTransaction> fetchById(String id) => guard(() async {
        final snapshot = await _col.doc(id).get();
        if (!snapshot.exists) throw const NotFoundException();
        final index = await relations.load();
        return RecurringTransaction.fromJson(index.attach(snapshot.asJson));
      });

  Future<RecurringTransaction> create(RecurringTransaction recurring) =>
      guard(() async {
        final ref = _col.doc();
        await ref.set({
          ...recurring.toInsertJson(),
          'user_id': userId,
          ...createdFields(),
        });
        return fetchById(ref.id);
      });

  Future<RecurringTransaction> update(RecurringTransaction recurring) =>
      guard(() async {
        await _col.doc(recurring.id).update({
          ...recurring.toUpdateJson(),
          ...updatedFields(),
        });
        return fetchById(recurring.id);
      });

  Future<RecurringTransaction> setActive(String id, {required bool active}) =>
      guard(() async {
        await _col.doc(id).update({
          'is_active': active,
          ...updatedFields(),
        });
        return fetchById(id);
      });

  /// Deletes a schedule. Transactions it already posted are untouched — they are
  /// real movements of money, not artefacts of the schedule.
  Future<void> delete(String id) => guard(() => _col.doc(id).delete());
}
