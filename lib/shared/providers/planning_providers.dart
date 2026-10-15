import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/enums.dart';
import '../../core/utils/money.dart';
import '../models/bill.dart';
import '../models/budget.dart';
import '../models/calculations.dart';
import '../models/lending.dart';
import '../models/savings_goal.dart';
import '../models/subscription.dart';
import '../models/transaction.dart';
import 'account_providers.dart';
import 'auth_providers.dart';
import 'dashboard_providers.dart';
import 'profile_providers.dart';
import 'repository_providers.dart';

// ---------------------------------------------------------------------------
// Budgets
// ---------------------------------------------------------------------------

/// Budgets with their spending, which is what every screen actually wants: a
/// budget without its spend is not useful information.
class BudgetsController extends AsyncNotifier<List<BudgetProgress>> {
  @override
  Future<List<BudgetProgress>> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const [];
    final currency = ref.watch(currencyProvider);
    return ref
        .watch(budgetRepositoryProvider)
        .fetchProgress(fallbackCurrency: currency);
  }

  Future<void> create(Budget budget) async {
    await ref.read(budgetRepositoryProvider).create(budget);
    await _reload();
  }

  Future<void> save(Budget budget) async {
    await ref.read(budgetRepositoryProvider).update(budget);
    await _reload();
  }

  Future<void> setArchived(String id, {required bool archived}) async {
    await ref.read(budgetRepositoryProvider).setArchived(id, archived: archived);
    await _reload();
  }

  Future<void> delete(String id) async {
    await ref.read(budgetRepositoryProvider).delete(id);
    await _reload();
  }

  Future<void> refresh() => _reload();

  Future<void> _reload() async {
    ref.invalidateSelf();
    ref.invalidate(dashboardControllerProvider);
    await future;
  }
}

final budgetsControllerProvider =
    AsyncNotifierProvider<BudgetsController, List<BudgetProgress>>(
  BudgetsController.new,
);

final budgetProgressByIdProvider =
    Provider.family<BudgetProgress?, String>((ref, id) {
  final budgets = ref.watch(budgetsControllerProvider).valueOrNull;
  if (budgets == null) return null;
  for (final progress in budgets) {
    if (progress.budget.id == id) return progress;
  }
  return null;
});

/// Budgets at or over their alert threshold, for the dashboard warning card.
final budgetsNeedingAttentionProvider =
    Provider<List<BudgetProgress>>((ref) {
  final budgets = ref.watch(budgetsControllerProvider).valueOrNull ?? const [];
  final flagged = budgets
      .where((b) => b.isExceeded || b.isAtThreshold)
      .toList()
    ..sort((a, b) => b.percentUsed.compareTo(a.percentUsed));
  return flagged;
});

/// Category ids that already have an active budget, so the create form does not
/// offer them twice — the database also enforces uniqueness.
final budgetedCategoryIdsProvider = Provider<Set<String>>((ref) {
  final budgets = ref.watch(budgetsControllerProvider).valueOrNull ?? const [];
  return budgets
      .map((b) => b.budget.categoryId)
      .nonNulls
      .toSet();
});

// ---------------------------------------------------------------------------
// Savings goals
// ---------------------------------------------------------------------------

class SavingsController extends AsyncNotifier<List<SavingsGoal>> {
  @override
  Future<List<SavingsGoal>> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const [];
    return ref.watch(savingsRepositoryProvider).fetchAll();
  }

  Future<SavingsGoal> create(SavingsGoal goal) async {
    final created = await ref.read(savingsRepositoryProvider).create(goal);
    await _reload();
    return created;
  }

  Future<void> save(SavingsGoal goal) async {
    await ref.read(savingsRepositoryProvider).update(goal);
    await _reload();
  }

  Future<void> contribute({
    required SavingsGoal goal,
    required Money amount,
    DateTime? occurredOn,
    String? note,
    String? fromAccountId,
  }) async {
    await ref.read(savingsRepositoryProvider).contribute(
          goal: goal,
          amount: amount,
          occurredOn: occurredOn,
          note: note,
          fromAccountId: fromAccountId,
        );
    ref.invalidate(savingsContributionsProvider(goal.id));
    // A contribution that moved money between accounts changed balances too.
    ref.invalidate(accountsControllerProvider);
    await _reload();
  }

  Future<void> withdraw({
    required SavingsGoal goal,
    required Money amount,
    DateTime? occurredOn,
    String? note,
    String? toAccountId,
  }) async {
    await ref.read(savingsRepositoryProvider).withdraw(
          goal: goal,
          amount: amount,
          occurredOn: occurredOn,
          note: note,
          toAccountId: toAccountId,
        );
    ref.invalidate(savingsContributionsProvider(goal.id));
    ref.invalidate(accountsControllerProvider);
    await _reload();
  }

  Future<void> markComplete(String id) async {
    await ref.read(savingsRepositoryProvider).markComplete(id);
    await _reload();
  }

  Future<void> setArchived(String id, {required bool archived}) async {
    await ref
        .read(savingsRepositoryProvider)
        .setArchived(id, archived: archived);
    await _reload();
  }

  Future<void> delete(String id) async {
    await ref.read(savingsRepositoryProvider).delete(id);
    await _reload();
  }

  Future<void> refresh() => _reload();

  Future<void> _reload() async {
    ref.invalidateSelf();
    ref.invalidate(dashboardControllerProvider);
    await future;
  }
}

final savingsControllerProvider =
    AsyncNotifierProvider<SavingsController, List<SavingsGoal>>(
  SavingsController.new,
);

final savingsGoalByIdProvider =
    Provider.family<SavingsGoal?, String>((ref, id) {
  final goals = ref.watch(savingsControllerProvider).valueOrNull;
  if (goals == null) return null;
  for (final goal in goals) {
    if (goal.id == id) return goal;
  }
  return null;
});

final savingsContributionsProvider =
    FutureProvider.family<List<SavingsContribution>, String>((ref, goalId) {
  return ref.watch(savingsRepositoryProvider).fetchContributions(goalId);
});

/// Combined progress across active goals, for the savings summary card.
final savingsTotalsProvider =
    Provider<({Money saved, Money target, double percent})>((ref) {
  final currency = ref.watch(currencyProvider);
  final goals = ref.watch(savingsControllerProvider).valueOrNull ?? const [];

  var saved = Money.zero(currency);
  var target = Money.zero(currency);

  for (final goal in goals) {
    if (goal.isArchived || goal.targetAmount.currency != currency) continue;
    saved += goal.currentAmount;
    target += goal.targetAmount;
  }

  return (
    saved: saved,
    target: target,
    percent: target.isZero ? 0.0 : saved.percentOf(target).clamp(0, 100),
  );
});

// ---------------------------------------------------------------------------
// Lending — money lent to, or borrowed from, someone who is not an account
// ---------------------------------------------------------------------------

class LendingController extends AsyncNotifier<List<LendingRecord>> {
  @override
  Future<List<LendingRecord>> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const [];
    return ref.watch(lendingRepositoryProvider).fetchAll();
  }

  Future<LendingRecord> create({
    required String personName,
    required LendingKind kind,
    required Money principal,
    required String accountId,
    DateTime? date,
    String? notes,
    DateTime? dueDate,
  }) async {
    final created = await ref.read(lendingRepositoryProvider).create(
          personName: personName,
          kind: kind,
          principal: principal,
          accountId: accountId,
          date: date,
          notes: notes,
          dueDate: dueDate,
        );
    ref.invalidate(accountsControllerProvider);
    await _reload();
    return created;
  }

  Future<void> recordRepayment({
    required LendingRecord lending,
    required Money amount,
    DateTime? date,
    String? notes,
  }) async {
    await ref.read(lendingRepositoryProvider).recordRepayment(
          lending: lending,
          amount: amount,
          date: date,
          notes: notes,
        );
    ref.invalidate(lendingHistoryProvider(lending.id));
    ref.invalidate(accountsControllerProvider);
    await _reload();
  }

  Future<void> save(LendingRecord lending) async {
    await ref.read(lendingRepositoryProvider).update(lending);
    await _reload();
  }

  Future<void> delete(String id) async {
    await ref.read(lendingRepositoryProvider).delete(id);
    ref.invalidate(lendingHistoryProvider(id));
    ref.invalidate(accountsControllerProvider);
    await _reload();
  }

  Future<void> refresh() => _reload();

  Future<void> _reload() async {
    ref.invalidateSelf();
    await future;
  }
}

final lendingControllerProvider =
    AsyncNotifierProvider<LendingController, List<LendingRecord>>(
  LendingController.new,
);

final lendingByIdProvider = Provider.family<LendingRecord?, String>((ref, id) {
  final lendings = ref.watch(lendingControllerProvider).valueOrNull;
  if (lendings == null) return null;
  for (final lending in lendings) {
    if (lending.id == id) return lending;
  }
  return null;
});

final lendingHistoryProvider =
    FutureProvider.family<List<Transaction>, String>((ref, lendingId) {
  return ref.watch(lendingRepositoryProvider).fetchHistory(lendingId);
});

/// What you're owed minus what you owe, across open lendings in the app's
/// currency — the net figure a summary card wants.
final lendingNetProvider = Provider<Money>((ref) {
  final currency = ref.watch(currencyProvider);
  final lendings = ref.watch(lendingControllerProvider).valueOrNull ?? const [];

  var net = Money.zero(currency);
  for (final lending in lendings) {
    if (lending.isSettled || lending.currency != currency) continue;
    net += lending.kind.isReceivable ? lending.outstanding : -lending.outstanding;
  }
  return net;
});

// ---------------------------------------------------------------------------
// Bills
// ---------------------------------------------------------------------------

class BillsController extends AsyncNotifier<List<Bill>> {
  @override
  Future<List<Bill>> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const [];
    return ref.watch(billRepositoryProvider).fetchAll();
  }

  Future<void> create(Bill bill) async {
    await ref.read(billRepositoryProvider).create(bill);
    await _reload();
  }

  Future<void> save(Bill bill) async {
    await ref.read(billRepositoryProvider).update(bill);
    await _reload();
  }

  /// Records payment, which also creates the expense transaction.
  Future<String> markPaid({
    required String billId,
    required String accountId,
    DateTime? paidOn,
    Money? amount,
  }) async {
    final transactionId = await ref.read(billRepositoryProvider).markPaid(
          billId: billId,
          accountId: accountId,
          paidOn: paidOn,
          amount: amount,
        );
    ref.invalidate(accountsControllerProvider);
    await _reload();
    return transactionId;
  }

  Future<void> setArchived(String id, {required bool archived}) async {
    await ref.read(billRepositoryProvider).setArchived(id, archived: archived);
    await _reload();
  }

  Future<void> delete(String id) async {
    await ref.read(billRepositoryProvider).delete(id);
    await _reload();
  }

  Future<void> refresh() => _reload();

  Future<void> _reload() async {
    ref.invalidateSelf();
    ref.invalidate(dashboardControllerProvider);
    await future;
  }
}

final billsControllerProvider =
    AsyncNotifierProvider<BillsController, List<Bill>>(BillsController.new);

/// Bills grouped into the urgency buckets the Bills screen renders.
final billBucketsProvider =
    Provider<Map<BillBucket, List<Bill>>>((ref) {
  final bills = ref.watch(billsControllerProvider).valueOrNull ?? const [];
  return BillTotals.groupByBucket(bills);
});

final outstandingBillsTotalProvider = Provider<Money>((ref) {
  final currency = ref.watch(currencyProvider);
  final bills = ref.watch(billsControllerProvider).valueOrNull ?? const [];
  return BillTotals.outstanding(bills, currency);
});

final billByIdProvider = Provider.family<Bill?, String>((ref, id) {
  final bills = ref.watch(billsControllerProvider).valueOrNull;
  if (bills == null) return null;
  for (final bill in bills) {
    if (bill.id == id) return bill;
  }
  return null;
});

// ---------------------------------------------------------------------------
// Subscriptions
// ---------------------------------------------------------------------------

class SubscriptionsController extends AsyncNotifier<List<Subscription>> {
  @override
  Future<List<Subscription>> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const [];
    return ref.watch(subscriptionRepositoryProvider).fetchAll();
  }

  Future<void> create(Subscription subscription) async {
    await ref.read(subscriptionRepositoryProvider).create(subscription);
    await _reload();
  }

  Future<void> save(Subscription subscription) async {
    await ref.read(subscriptionRepositoryProvider).update(subscription);
    await _reload();
  }

  Future<void> setActive(String id, {required bool active}) async {
    await ref
        .read(subscriptionRepositoryProvider)
        .setActive(id, active: active);
    await _reload();
  }

  Future<void> delete(String id) async {
    await ref.read(subscriptionRepositoryProvider).delete(id);
    await _reload();
  }

  Future<void> refresh() => _reload();

  Future<void> _reload() async {
    ref.invalidateSelf();
    await future;
  }
}

final subscriptionsControllerProvider =
    AsyncNotifierProvider<SubscriptionsController, List<Subscription>>(
  SubscriptionsController.new,
);

/// Monthly and yearly subscription cost, normalised across billing periods so
/// yearly and monthly plans can be added together.
final subscriptionTotalsProvider =
    Provider<({Money monthly, Money yearly, int activeCount})>((ref) {
  final currency = ref.watch(currencyProvider);
  final subscriptions =
      ref.watch(subscriptionsControllerProvider).valueOrNull ?? const [];
  return (
    monthly: SubscriptionTotals.monthly(subscriptions, currency),
    yearly: SubscriptionTotals.yearly(subscriptions, currency),
    activeCount:
        subscriptions.where((s) => s.isActive && !s.isArchived).length,
  );
});

final renewingSoonProvider = Provider<List<Subscription>>((ref) {
  final subscriptions =
      ref.watch(subscriptionsControllerProvider).valueOrNull ?? const [];
  return SubscriptionTotals.renewingSoon(subscriptions);
});

final subscriptionByIdProvider =
    Provider.family<Subscription?, String>((ref, id) {
  final subscriptions = ref.watch(subscriptionsControllerProvider).valueOrNull;
  if (subscriptions == null) return null;
  for (final subscription in subscriptions) {
    if (subscription.id == id) return subscription;
  }
  return null;
});

// ---------------------------------------------------------------------------
// Recurring transactions
// ---------------------------------------------------------------------------

class RecurringController extends AsyncNotifier<List<RecurringTransaction>> {
  @override
  Future<List<RecurringTransaction>> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const [];
    return ref.watch(recurringRepositoryProvider).fetchAll();
  }

  Future<void> create(RecurringTransaction recurring) async {
    await ref.read(recurringRepositoryProvider).create(recurring);
    await _reload();
  }

  Future<void> save(RecurringTransaction recurring) async {
    await ref.read(recurringRepositoryProvider).update(recurring);
    await _reload();
  }

  Future<void> setActive(String id, {required bool active}) async {
    await ref.read(recurringRepositoryProvider).setActive(id, active: active);
    await _reload();
  }

  Future<void> delete(String id) async {
    await ref.read(recurringRepositoryProvider).delete(id);
    await _reload();
  }

  Future<void> refresh() => _reload();

  Future<void> _reload() async {
    ref.invalidateSelf();
    await future;
  }
}

final recurringControllerProvider =
    AsyncNotifierProvider<RecurringController, List<RecurringTransaction>>(
  RecurringController.new,
);

final recurringByIdProvider =
    Provider.family<RecurringTransaction?, String>((ref, id) {
  final items = ref.watch(recurringControllerProvider).valueOrNull;
  if (items == null) return null;
  for (final item in items) {
    if (item.id == id) return item;
  }
  return null;
});
