import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/enums.dart';
import '../../core/utils/money.dart';
import '../models/account.dart';
import '../models/calculations.dart';
import '../models/category.dart';
import 'auth_providers.dart';
import 'profile_providers.dart';
import 'repository_providers.dart';

/// The user's accounts.
class AccountsController extends AsyncNotifier<List<Account>> {
  @override
  Future<List<Account>> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const [];
    return ref.watch(accountRepositoryProvider).fetchAll();
  }

  Future<Account> create(Account account) async {
    final created = await ref.read(accountRepositoryProvider).create(account);
    ref.invalidateSelf();
    await future;
    return created;
  }

  Future<Account> save(Account account) async {
    final updated = await ref.read(accountRepositoryProvider).update(account);
    ref.invalidateSelf();
    await future;
    return updated;
  }

  Future<void> setArchived(String id, {required bool archived}) async {
    await ref
        .read(accountRepositoryProvider)
        .setArchived(id, archived: archived);
    ref.invalidateSelf();
    await future;
  }

  Future<void> updateInitialBalance(String id, Money balance) async {
    await ref.read(accountRepositoryProvider).updateInitialBalance(id, balance);
    ref.invalidateSelf();
    await future;
  }

  Future<void> delete(String id, {bool force = false}) async {
    await ref.read(accountRepositoryProvider).delete(id, force: force);
    ref.invalidateSelf();
    await future;
  }

  Future<void> reorder(List<String> orderedIds) async {
    // Applied locally first so the list does not jump back before the writes
    // finish; a failure re-fetches and restores the server's order.
    final current = state.valueOrNull;
    if (current != null) {
      final byId = {for (final a in current) a.id: a};
      final reordered = orderedIds
          .map((id) => byId[id])
          .nonNulls
          .toList(growable: false);
      state = AsyncValue.data(reordered);
    }

    try {
      await ref.read(accountRepositoryProvider).reorder(orderedIds);
    } finally {
      ref.invalidateSelf();
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue<List<Account>>.loading();
    state = await AsyncValue.guard(
      () => ref.read(accountRepositoryProvider).fetchAll(),
    );
  }
}

final accountsControllerProvider =
    AsyncNotifierProvider<AccountsController, List<Account>>(
  AccountsController.new,
);

/// Active accounts only, for pickers.
final activeAccountsProvider = Provider<List<Account>>((ref) {
  return ref.watch(accountsControllerProvider).maybeWhen(
        data: (accounts) =>
            accounts.where((a) => a.isActive && !a.isArchived).toList(),
        orElse: () => const [],
      );
});

final accountByIdProvider = Provider.family<Account?, String?>((ref, id) {
  if (id == null) return null;
  final accounts = ref.watch(accountsControllerProvider).valueOrNull;
  if (accounts == null) return null;
  for (final account in accounts) {
    if (account.id == id) return account;
  }
  return null;
});

/// Total balance across active accounts, plus how many were left out because
/// they are held in another currency.
final totalBalanceProvider =
    Provider<({Money total, int excludedCount})>((ref) {
  final currency = ref.watch(currencyProvider);
  final accounts = ref.watch(accountsControllerProvider).valueOrNull ?? const [];
  return AccountTotals.balance(accounts, currency);
});

/// The account a new transaction should default to: the user's chosen default,
/// or the first active account.
final defaultAccountProvider = Provider<Account?>((ref) {
  final accounts = ref.watch(activeAccountsProvider);
  if (accounts.isEmpty) return null;

  final preferredId = ref.watch(settingsControllerProvider).maybeWhen(
        data: (settings) => settings.defaultAccountId,
        orElse: () => null,
      );

  if (preferredId != null) {
    for (final account in accounts) {
      if (account.id == preferredId) return account;
    }
  }
  return accounts.first;
});

/// The user's categories.
class CategoriesController extends AsyncNotifier<List<Category>> {
  @override
  Future<List<Category>> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const [];
    return ref.watch(categoryRepositoryProvider).fetchAll();
  }

  Future<Category> create(Category category) async {
    final created = await ref.read(categoryRepositoryProvider).create(category);
    ref.invalidateSelf();
    await future;
    return created;
  }

  Future<Category> save(Category category) async {
    final updated = await ref.read(categoryRepositoryProvider).update(category);
    ref.invalidateSelf();
    await future;
    return updated;
  }

  Future<void> setArchived(String id, {required bool archived}) async {
    await ref
        .read(categoryRepositoryProvider)
        .setArchived(id, archived: archived);
    ref.invalidateSelf();
    await future;
  }

  Future<void> delete(String id) async {
    await ref.read(categoryRepositoryProvider).delete(id);
    ref.invalidateSelf();
    await future;
  }

  Future<void> reorder(List<String> orderedIds) async {
    await ref.read(categoryRepositoryProvider).reorder(orderedIds);
    ref.invalidateSelf();
    await future;
  }

  Future<void> refresh() async {
    state = const AsyncValue<List<Category>>.loading();
    state = await AsyncValue.guard(
      () => ref.read(categoryRepositoryProvider).fetchAll(),
    );
  }
}

final categoriesControllerProvider =
    AsyncNotifierProvider<CategoriesController, List<Category>>(
  CategoriesController.new,
);

/// Categories of one kind, unarchived, for a transaction form's picker.
final categoriesByKindProvider =
    Provider.family<List<Category>, CategoryKind>((ref, kind) {
  final categories =
      ref.watch(categoriesControllerProvider).valueOrNull ?? const [];
  return categories
      .where((c) => c.kind == kind && !c.isArchived)
      .toList(growable: false);
});

final categoryByIdProvider = Provider.family<Category?, String?>((ref, id) {
  if (id == null) return null;
  final categories = ref.watch(categoriesControllerProvider).valueOrNull;
  if (categories == null) return null;
  for (final category in categories) {
    if (category.id == id) return category;
  }
  return null;
});

/// How many transactions use a category, for the delete confirmation.
final categoryUsageProvider =
    FutureProvider.family<int, String>((ref, categoryId) {
  return ref.watch(categoryRepositoryProvider).usageCount(categoryId);
});
