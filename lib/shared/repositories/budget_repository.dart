import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/errors/app_exception.dart';
import '../../core/services/firebase_service.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/money.dart';
import '../models/budget.dart';
import '../models/json_map.dart';
import 'base_repository.dart';

/// Budgets, at `users/{uid}/budgets`.
class BudgetRepository extends BaseRepository {
  BudgetRepository({super.firestore});

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseService.budgets(userId);

  /// Budgets, each with its category attached.
  ///
  /// Firestore has no joins, so the categories are fetched once and matched in
  /// memory. One read per budget to resolve a name would turn a dozen budgets
  /// into a dozen extra billed reads, every time the dashboard opened.
  Future<List<Budget>> fetchAll({bool includeArchived = false}) =>
      guard(() async {
        final snapshot = await _col.orderBy('created_at').get();
        if (snapshot.docs.isEmpty) return const <Budget>[];

        final index = await relations.load();
        final budgets = index
            .attachAll(snapshot.docs.map((doc) => doc.asJson))
            .map(Budget.fromJson);

        if (includeArchived) return budgets.toList(growable: false);
        return budgets.where((b) => !b.isArchived).toList(growable: false);
      });

  Future<Budget> fetchById(String id) => guard(() async {
        final snapshot = await _col.doc(id).get();
        if (!snapshot.exists) throw const NotFoundException();
        final index = await relations.load();
        return Budget.fromJson(index.attach(snapshot.asJson));
      });

  /// Budgets paired with the spending recorded against them.
  ///
  /// The spend figure is maintained on each budget document by the
  /// `onTransactionWritten` trigger, not computed here. Summing a period of
  /// transactions per budget on the client would mean reading — and paying for —
  /// the whole period's transactions on every dashboard open, and two devices
  /// posting at once would each compute from a different snapshot.
  ///
  /// `spent_period_start` says which period the stored figure belongs to. When
  /// the period has rolled over and nothing has been posted since, the stored
  /// figure is last period's, so it reads as zero rather than carrying forward.
  /// That self-heals on the next transaction.
  Future<List<BudgetProgress>> fetchProgress({
    DateTime? reference,
    String fallbackCurrency = 'LKR',
  }) =>
      guard(() async {
        final budgets = await fetchAll();
        if (budgets.isEmpty) return const <BudgetProgress>[];

        final at = reference ?? DateTime.now();

        return budgets.map((budget) {
          final range = budget.currentRange(at);
          final storedStart = budget.spentPeriodStart;
          final samePeriod = storedStart != null &&
              AppDateUtils.isSameDay(storedStart, range.start);

          return BudgetProgress(
            budget: budget,
            spent: samePeriod && budget.spent != null
                ? budget.spent!
                : Money.zero(budget.amount.currency),
            range: range,
          );
        }).toList(growable: false);
      });

  Future<Budget> create(Budget budget) => guard(() async {
        final ref = _col.doc();
        await ref.set({
          ...budget.toInsertJson(),
          'user_id': userId,
          // Derived fields, seeded so the rules can require they only ever move
          // under the trigger's hand afterwards.
          minorKey('spent'): 0,
          'spent_period_start': null,
          ...createdFields(),
        });
        return fetchById(ref.id);
      });

  Future<Budget> update(Budget budget) => guard(() async {
        await _col.doc(budget.id).update({
          ...budget.toUpdateJson(),
          ...updatedFields(),
        });
        return fetchById(budget.id);
      });

  Future<Budget> setArchived(String id, {required bool archived}) =>
      guard(() async {
        await _col.doc(id).update({
          'is_archived': archived,
          ...updatedFields(),
        });
        return fetchById(id);
      });

  /// Budgets carry no history of their own, so deleting one is safe: no
  /// transaction points at a budget, and the spend figure is derived.
  Future<void> delete(String id) => guard(() => _col.doc(id).delete());
}
