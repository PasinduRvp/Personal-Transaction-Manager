import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/enums.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/money.dart';
import '../models/calculations.dart';
import '../models/transaction.dart';
import '../models/transaction_candidate.dart';
import '../models/transaction_query.dart';
import '../repositories/transaction_repository.dart';
import 'account_providers.dart';
import 'auth_providers.dart';
import 'repository_providers.dart';

/// The active search, filter and sort state of the transaction list.
///
/// Held separately from the results so changing a filter does not rebuild the
/// query object the list is already paging through — the notifier below reacts
/// to a new value by starting a fresh page one.
class TransactionQueryController extends Notifier<TransactionQuery> {
  @override
  TransactionQuery build() => const TransactionQuery();

  void setSearch(String? term) {
    final trimmed = term?.trim();
    state = state.copyWith(search: trimmed?.isEmpty == true ? null : trimmed);
  }

  void setSort(TransactionSort sort) => state = state.copyWith(sort: sort);

  void toggleType(TransactionType type) {
    final next = Set<TransactionType>.from(state.types);
    next.contains(type) ? next.remove(type) : next.add(type);
    state = state.copyWith(types: next);
  }

  void toggleCategory(String id) {
    final next = Set<String>.from(state.categoryIds);
    next.contains(id) ? next.remove(id) : next.add(id);
    state = state.copyWith(categoryIds: next);
  }

  void toggleAccount(String id) {
    final next = Set<String>.from(state.accountIds);
    next.contains(id) ? next.remove(id) : next.add(id);
    state = state.copyWith(accountIds: next);
  }

  void togglePaymentMethod(PaymentMethod method) {
    final next = Set<PaymentMethod>.from(state.paymentMethods);
    next.contains(method) ? next.remove(method) : next.add(method);
    state = state.copyWith(paymentMethods: next);
  }

  void toggleSource(TransactionSource source) {
    final next = Set<TransactionSource>.from(state.sources);
    next.contains(source) ? next.remove(source) : next.add(source);
    state = state.copyWith(sources: next);
  }

  void toggleStatus(TransactionStatus status) {
    final next = Set<TransactionStatus>.from(state.statuses);
    next.contains(status) ? next.remove(status) : next.add(status);
    state = state.copyWith(statuses: next);
  }

  void setDateRange(DateRange? range) =>
      state = state.copyWith(dateRange: range);

  void setAmountRange({Money? min, Money? max}) =>
      state = state.copyWith(minAmount: min, maxAmount: max);

  void setIncludeTransfers(bool include) =>
      state = state.copyWith(includeTransfers: include);

  void setOnlyWithAttachments(bool only) =>
      state = state.copyWith(onlyWithAttachments: only);

  /// Clears the filters but keeps the search text and sort order, which is what
  /// a "Clear filters" button should do.
  void clearFilters() => state = state.clearFilters();

  void reset() => state = const TransactionQuery();

  /// Replaces the whole query, used when applying a filter sheet at once.
  void apply(TransactionQuery query) => state = query;
}

final transactionQueryProvider =
    NotifierProvider<TransactionQueryController, TransactionQuery>(
  TransactionQueryController.new,
);

/// The paged transaction list.
///
/// Pages are appended rather than replacing the list, and the notifier tracks
/// whether a further page exists, so an infinite scroll can stop asking. A page
/// request already in flight is ignored rather than queued — a fast scroll would
/// otherwise fire several identical requests and append duplicates.
///
/// Paging is by cursor, not by page number: the repository hands back the position
/// it stopped at and the next request resumes from there. That is both what
/// Firestore supports and what keeps the list stable when a transaction is added
/// while the user is partway down it.
class TransactionListController extends AsyncNotifier<Paged<Transaction>> {
  bool _isFetchingMore = false;

  @override
  Future<Paged<Transaction>> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) {
      return const Paged<Transaction>(items: [], hasMore: false);
    }

    // Re-runs whenever the query changes, which is the intended behaviour: a new
    // filter means a new page one.
    final query = ref.watch(transactionQueryProvider);

    final page = await ref.read(transactionRepositoryProvider).fetchPage(
          query: query,
        );

    return Paged<Transaction>(
      items: page.items,
      cursor: page.cursor,
      hasMore: page.hasMore,
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || _isFetchingMore) return;

    _isFetchingMore = true;
    state = AsyncValue.data(current.copyWith(isLoadingMore: true));

    try {
      final next = await ref.read(transactionRepositoryProvider).fetchPage(
            query: ref.read(transactionQueryProvider),
            after: current.cursor as TransactionCursor?,
          );

      state = AsyncValue.data(
        current.copyWith(
          items: [...current.items, ...next.items],
          cursor: next.cursor,
          hasMore: next.hasMore,
          isLoadingMore: false,
        ),
      );
    } on Object catch (error, stack) {
      // Keep the pages already loaded; surface the failure without throwing the
      // user back to an empty list.
      state = AsyncValue.data(current.copyWith(isLoadingMore: false));
      ref.read(_listErrorProvider.notifier).state =
          AsyncValue<void>.error(error, stack);
    } finally {
      _isFetchingMore = false;
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue<Paged<Transaction>>.loading();
    state = await AsyncValue.guard(() async {
      final page = await ref.read(transactionRepositoryProvider).fetchPage(
            query: ref.read(transactionQueryProvider),
          );
      return Paged<Transaction>(
        items: page.items,
        cursor: page.cursor,
        hasMore: page.hasMore,
      );
    });
  }

  /// Removes a transaction locally and then on the server.
  ///
  /// The optimistic removal makes a swipe-to-delete feel instant; a failure puts
  /// the row back, because silently losing a delete is worse than a brief flicker.
  Future<void> delete(Transaction transaction) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current.copyWith(
          items: current.items
              .where((t) =>
                  t.id != transaction.id &&
                  (transaction.transferGroupId == null ||
                      t.transferGroupId != transaction.transferGroupId))
              .toList(),
        ),
      );
    }

    try {
      await ref.read(transactionRepositoryProvider).delete(transaction);
      _invalidateDependents();
    } on Object {
      if (current != null) state = AsyncValue.data(current);
      rethrow;
    }
  }

  void _invalidateDependents() {
    ref.invalidate(accountsControllerProvider);
  }
}

final transactionListControllerProvider =
    AsyncNotifierProvider<TransactionListController, Paged<Transaction>>(
  TransactionListController.new,
);

/// Carries a load-more failure to the UI without discarding the loaded pages.
final _listErrorProvider =
    StateProvider<AsyncValue<void>>((ref) => const AsyncValue.data(null));

final transactionListErrorProvider = Provider<Object?>(
  (ref) => ref.watch(_listErrorProvider).error,
);

/// The list grouped into day sections, ready to render.
final groupedTransactionsProvider =
    Provider<List<TransactionDayGroup>>((ref) {
  final paged = ref.watch(transactionListControllerProvider).valueOrNull;
  if (paged == null) return const [];
  return TransactionGrouping.byDay(paged.items);
});

/// How many transactions match the current query, for the results header.
///
/// The result says whether the number is exact. Firestore can count a query it
/// can express entirely as filters; when part of the filtering has to happen on
/// the client, the count it returns is an upper bound, and the header says "about"
/// rather than quietly showing a number that disagrees with the list below it.
final transactionCountProvider = FutureProvider<TransactionCountResult>((ref) {
  final query = ref.watch(transactionQueryProvider);
  return ref.watch(transactionRepositoryProvider).countMatching(query);
});

/// One transaction with its splits, for the detail screen.
final transactionDetailProvider =
    FutureProvider.family<Transaction, String>((ref, id) {
  return ref.watch(transactionRepositoryProvider).fetchById(id);
});

/// Both legs of a transfer.
final transferGroupProvider =
    FutureProvider.family<List<Transaction>, String>((ref, groupId) {
  return ref.watch(transactionRepositoryProvider).fetchTransferGroup(groupId);
});

/// Writes: creating, editing and duplicating.
///
/// Kept apart from the list controller so a form can await a single operation and
/// show its own progress and errors, without the list's paging state getting
/// involved.
class TransactionWriter extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<Transaction> create(Transaction transaction) async {
    state = const AsyncValue<void>.loading();
    try {
      final created =
          await ref.read(transactionRepositoryProvider).create(transaction);
      state = const AsyncValue.data(null);
      _invalidateReaders();
      return created;
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
      rethrow;
    }
  }

  Future<Transaction> save(Transaction transaction) async {
    state = const AsyncValue<void>.loading();
    try {
      final updated =
          await ref.read(transactionRepositoryProvider).update(transaction);
      state = const AsyncValue.data(null);
      _invalidateReaders();
      ref.invalidate(transactionDetailProvider(transaction.id));
      return updated;
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
      rethrow;
    }
  }

  Future<String> createTransfer({
    required String fromAccountId,
    required String toAccountId,
    required Money amount,
    required DateTime date,
    String? description,
    String? notes,
    PaymentMethod? paymentMethod,
    String? documentId,
  }) async {
    state = const AsyncValue<void>.loading();
    try {
      final groupId =
          await ref.read(transactionRepositoryProvider).createTransfer(
                fromAccountId: fromAccountId,
                toAccountId: toAccountId,
                amount: amount,
                date: date,
                description: description,
                notes: notes,
                paymentMethod: paymentMethod,
                documentId: documentId,
              );
      state = const AsyncValue.data(null);
      _invalidateReaders();
      return groupId;
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
      rethrow;
    }
  }

  Future<Transaction> duplicate(Transaction source) async {
    final copy =
        await ref.read(transactionRepositoryProvider).duplicate(source);
    _invalidateReaders();
    return copy;
  }

  Future<void> confirmPending(String id) async {
    await ref
        .read(transactionRepositoryProvider)
        .setStatus(id, TransactionStatus.confirmed);
    _invalidateReaders();
    ref.invalidate(transactionDetailProvider(id));
  }

  Future<void> replaceSplits({
    required Transaction transaction,
    required List<TransactionSplit> splits,
  }) async {
    await ref.read(transactionRepositoryProvider).replaceSplits(
          transaction: transaction,
          splits: splits,
        );
    ref.invalidate(transactionDetailProvider(transaction.id));
    _invalidateReaders();
  }

  Future<void> setAttachment(String transactionId, String? documentId) async {
    await ref
        .read(transactionRepositoryProvider)
        .setDocument(transactionId, documentId);
    ref.invalidate(transactionDetailProvider(transactionId));
  }

  /// Looks for existing transactions resembling the one being entered.
  ///
  /// Advisory: the form shows the matches and lets the user continue anyway.
  Future<List<DuplicateMatch>> findDuplicates({
    required Money amount,
    required DateTime date,
    String? merchant,
    String? accountId,
    String? excludeTransactionId,
  }) =>
      ref.read(transactionRepositoryProvider).findDuplicates(
            amount: amount,
            date: date,
            merchant: merchant,
            accountId: accountId,
            excludeTransactionId: excludeTransactionId,
          );

  void _invalidateReaders() {
    ref.invalidate(transactionListControllerProvider);
    ref.invalidate(accountsControllerProvider);
    ref.invalidate(transactionCountProvider);
  }
}

final transactionWriterProvider =
    AsyncNotifierProvider<TransactionWriter, void>(TransactionWriter.new);
