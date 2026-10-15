import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/enums.dart';
import '../../core/services/firebase_service.dart';
import '../../core/utils/app_date_utils.dart';
import '../models/json_map.dart';
import 'base_repository.dart';
import 'ledger_writer.dart';
import '../models/budget.dart';

/// The work a scheduler used to do, run when the app opens.
///
/// On the paid plan a Cloud Scheduler job ran this daily across every account.
/// Without a server it runs on launch, for the signed-in user only — which has one
/// genuine consequence worth being honest about:
///
/// **Nothing happens while the app is closed.** A recurring transaction due on the
/// 1st is posted the next time the app is opened, not on the 1st. Bill reminders
/// appear when you look, not before. The *dates* are still correct — a transaction
/// missed for three months posts three transactions, one per occurrence, each
/// dated when it was actually due — so the ledger ends up identical. Only the
/// notification is late.
///
/// Everything here is **idempotent**, because "run whenever the app opens" means
/// running many times a day. Posted transactions use an id derived from the
/// schedule and the occurrence date, so a second run writes the same document
/// rather than a duplicate; notifications do the same with their own ids.
class MaintenanceRunner extends BaseRepository {
  MaintenanceRunner({super.firestore});

  /// How often this is worth doing. Opening the app twenty times a day should not
  /// mean twenty sweeps of every bill and subscription.
  static const Duration _interval = Duration(hours: 6);

  /// Runs the sweep if it has not run recently.
  ///
  /// Never throws: maintenance failing must not stop the user reaching their data,
  /// and the next launch tries again.
  Future<void> runIfDue({bool force = false}) async {
    try {
      final profileRef = FirebaseService.userDoc(userId);
      final profile = await profileRef.get();

      if (!profile.exists) return;

      final lastRun = profile.asJson.dateOrNull('last_maintenance_run');
      if (!force &&
          lastRun != null &&
          DateTime.now().difference(lastRun) < _interval) {
        return;
      }

      final posted = await _postDueRecurring();
      final overdue = await _advanceOverdueBills();
      final renewed = await _rollSubscriptions();
      await _sweepNotifications();

      await profileRef.update({
        'last_maintenance_run': FieldValue.serverTimestamp(),
      });

      if (posted + overdue + renewed > 0) {
        log.info('Maintenance: $posted recurring posted, $overdue bills '
            'overdue, $renewed subscriptions renewed');
      }
    } on Object catch (error, stack) {
      log.warning('Maintenance run failed', error, stack);
    }
  }

  // -------------------------------------------------------------------------
  // Recurring transactions
  // -------------------------------------------------------------------------

  /// Posts the transactions that recurring schedules are due to create.
  ///
  /// A schedule that has not run for three months posts three transactions, one per
  /// missed occurrence, each dated when it was due — the money moved three times
  /// and the ledger should say so. Capped at twelve per schedule per run: beyond
  /// that the schedule is so stale that silently posting a year of history would be
  /// a surprise rather than a service.
  Future<int> _postDueRecurring() async {
    final today = AppDateUtils.endOfDay(DateTime.now());

    final schedules = await FirebaseService.recurring(userId)
        .where('is_active', isEqualTo: true)
        .get();

    if (schedules.docs.isEmpty) return 0;

    final budgets = await _activeBudgets();
    var posted = 0;

    for (final schedule in schedules.docs) {
      final data = schedule.asJson;
      final accountId = data.strOrNull('account_id');
      final amount = data.money('amount');

      if (accountId == null || amount.isZero || amount.isNegative) continue;

      final endDate = data.dateOrNull('end_date');
      var next = data.dateOrNull('next_execution_date');
      final frequency =
          RecurrenceFrequency.fromWire(data.strOrNull('frequency'));
      final type = TransactionType.fromWire(data.strOrNull('type'));

      var created = 0;

      while (next != null && !next.isAfter(today) && created < 12) {
        if (endDate != null && next.isAfter(endDate)) break;

        // Derived from the schedule and the occurrence date, so a second run writes
        // the same document rather than a duplicate transaction.
        final id = 'rec_${schedule.id}_${dateOnly(next)}';
        final ref = FirebaseService.transactions(userId).doc(id);
        final occurrence = next;

        final wrote = await _createIfAbsent(ref, () {
          final description = data.str('name', fallback: 'Recurring');
          final merchant = data.strOrNull('merchant');

          return {
            'user_id': userId,
            'account_id': accountId,
            'category_id': data.strOrNull('category_id'),
            'type': type.wire,
            ...moneyFields('amount', amount),
            'description': description,
            'merchant': merchant,
            'payment_method': data.strOrNull('payment_method'),
            'transaction_date': Timestamp.fromDate(occurrence),
            'notes': data.strOrNull('notes'),
            'document_id': null,
            'source': TransactionSource.manual.wire,
            'status': TransactionStatus.confirmed.wire,
            'recurring_transaction_id': schedule.id,
            'is_split': false,
            'search_terms':
                searchTerms([description, merchant], prefixed: [merchant]),
            ...createdFields(),
          };
        }, budgets: budgets, effect: () => LedgerEffect(
              accountId: accountId,
              categoryId: data.strOrNull('category_id'),
              type: type,
              status: TransactionStatus.confirmed,
              currency: amount.currency,
              amountMinor: amount.minorUnits.abs(),
              date: occurrence,
              merchant: data.strOrNull('merchant'),
              paymentMethod: data.strOrNull('payment_method'),
              transferDirection: null,
            ));

        if (wrote) {
          created++;
          posted++;
        }

        next = AppDateUtils.advance(next, frequency);
      }

      if (created > 0 || next != null) {
        final finished = endDate != null && next != null && next.isAfter(endDate);
        await schedule.reference.update({
          if (next != null) 'next_execution_date': dateOnly(next),
          if (created > 0) 'last_executed_on': dateOnly(DateTime.now()),
          if (finished) 'is_active': false,
          ...updatedFields(),
        });
      }
    }

    return posted;
  }

  /// Writes a transaction and its ledger effect, unless the id already exists.
  ///
  /// `create` on an existing id fails, which is exactly the duplicate guard wanted —
  /// so the existence check and the write are one operation rather than a read
  /// followed by a race.
  Future<bool> _createIfAbsent(
    DocumentReference<Map<String, dynamic>> ref,
    Json Function() build, {
    required List<Budget> budgets,
    required LedgerEffect Function() effect,
  }) async {
    try {
      await db.runTransaction((tx) async {
        final existing = await tx.get(ref);
        if (existing.exists) throw _AlreadyPosted();

        tx.set(ref, build());

        LedgerWriter.apply(
          tx,
          userId: userId,
          before: null,
          after: effect(),
          budgets: budgets,
        );
      });
      return true;
    } on _AlreadyPosted {
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Bills
  // -------------------------------------------------------------------------

  /// Moves bills past their due date to `OVERDUE`.
  ///
  /// A stored status rather than one inferred from the date, because Firestore
  /// cannot filter on a computed value and the dashboard queries for it.
  Future<int> _advanceOverdueBills() async {
    final today = dateOnly(DateTime.now());

    final bills = await FirebaseService.bills(userId)
        .where('status', isEqualTo: BillStatus.unpaid.wire)
        .get();

    final due = bills.docs.where((doc) {
      final dueDate = doc.asJson.str('due_date');
      // `<` not `<=`: a bill due today is not yet overdue.
      return dueDate.isNotEmpty && dueDate.compareTo(today) < 0;
    }).toList();

    if (due.isEmpty) return 0;

    final batch = db.batch();
    for (final doc in due) {
      batch.update(doc.reference, {
        'status': BillStatus.overdue.wire,
        ...updatedFields(),
      });
    }
    await batch.commit();

    return due.length;
  }

  // -------------------------------------------------------------------------
  // Subscriptions
  // -------------------------------------------------------------------------

  /// Rolls subscriptions past their renewal date forward.
  ///
  /// No transaction is posted. A subscription is a commitment, and whether the card
  /// was actually charged is something the user's statement says — inventing the
  /// expense would take money out of an account that may not have lost it.
  Future<int> _rollSubscriptions() async {
    final today = AppDateUtils.endOfDay(DateTime.now());

    final subscriptions = await FirebaseService.subscriptions(userId)
        .where('is_active', isEqualTo: true)
        .get();

    var rolled = 0;
    final batch = db.batch();

    for (final doc in subscriptions.docs) {
      final data = doc.asJson;
      var next = data.dateOrNull('next_renewal_date');
      if (next == null || next.isAfter(today)) continue;

      final period = RecurrenceFrequency.fromWire(
        data.strOrNull('billing_period') ?? data.strOrNull('frequency'),
      );

      // Catch a lapsed subscription up to its next future date in one go, rather
      // than one period per launch.
      var guard = 0;
      while (!next!.isAfter(today) && guard < 60) {
        next = AppDateUtils.advance(next, period);
        guard++;
      }

      batch.update(doc.reference, {
        'next_renewal_date': dateOnly(next),
        ...updatedFields(),
      });
      rolled++;
    }

    if (rolled > 0) await batch.commit();
    return rolled;
  }

  // -------------------------------------------------------------------------
  // Housekeeping
  // -------------------------------------------------------------------------

  /// Removes notifications nobody will read again.
  ///
  /// Read ones older than 60 days, unread ones older than a year. A notification
  /// centre that only grows becomes a list nobody opens, and these documents are
  /// read on every dashboard refresh.
  Future<void> _sweepNotifications() async {
    final readCutoff = DateTime.now().subtract(const Duration(days: 60));
    final unreadCutoff = DateTime.now().subtract(const Duration(days: 365));

    for (final (isRead, cutoff) in [(true, readCutoff), (false, unreadCutoff)]) {
      final stale = await FirebaseService.notifications(userId)
          .where('is_read', isEqualTo: isRead)
          .where('created_at', isLessThan: Timestamp.fromDate(cutoff))
          .limit(200)
          .get();

      if (stale.docs.isEmpty) continue;

      final batch = db.batch();
      for (final doc in stale.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  Future<List<Budget>> _activeBudgets() async {
    final snapshot = await FirebaseService.budgets(userId).get();
    return snapshot.docs
        .map((doc) => Budget.fromJson(doc.asJson))
        .where((b) => !b.isArchived)
        .toList(growable: false);
  }
}

/// Signals that an occurrence had already been posted by an earlier run.
class _AlreadyPosted implements Exception {}
