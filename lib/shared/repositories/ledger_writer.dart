import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:cloud_firestore/cloud_firestore.dart' as fs show Transaction;

import '../../core/constants/enums.dart';
import '../../core/services/firebase_service.dart';
import '../../core/utils/app_date_utils.dart';
import '../models/budget.dart';
import '../models/json_map.dart';
import '../models/transaction.dart';

/// Keeps every derived figure in step with the transactions, from the client.
///
/// On the paid plan this was a Cloud Function triggered by the write. On the free
/// plan there is no server, so the same arithmetic runs here — but it runs *inside
/// the same Firestore transaction* as the document it derives from, which is a
/// trade worth understanding rather than glossing over.
///
/// **What is still guaranteed.**
///
///   * **Atomicity.** The transaction document, the account balance, the monthly
///     rollup and any affected budgets are written in one Firestore transaction.
///     Either all of it lands or none of it does. A dropped connection cannot
///     leave a balance that disagrees with the ledger.
///   * **Concurrency.** Every derived figure moves with `FieldValue.increment`,
///     which the server applies to whatever the value is when the write arrives.
///     Two devices posting at once both count. Reading a balance, adding to it and
///     writing it back — the obvious client-side approach — would make the later
///     write silently discard the earlier transaction.
///   * **Immediacy.** The balance changes in the same instant as the transaction,
///     so there is none of the eventual consistency a trigger introduced. This is
///     the one respect in which the free plan is *better*.
///
/// **What is lost.** Enforcement. A Cloud Function was the only writer of these
/// fields and the rules refused everyone else, so a tampered client could not
/// invent a balance. Here the client must be allowed to write them, and no rule
/// can check one document's increment against another document's amount.
///
/// For a personal ledger that is a defensible trade: the only person who could
/// falsify these figures is the account's owner, falsifying their own records. The
/// isolation that actually matters — that no user can read or write another
/// user's data — is unaffected, and remains entirely enforced by the rules.
class LedgerWriter {
  const LedgerWriter._();

  /// Applies the effect of creating, editing or deleting a transaction.
  ///
  /// [before] is null for a create, [after] is null for a delete. [budgets] is read
  /// by the caller beforehand, because the client SDK cannot run a query inside a
  /// Firestore transaction — only direct document reads. A budget created in the
  /// moment between that read and this write is missed, which self-heals on the
  /// next transaction posted into the same period.
  static void apply(
    fs.Transaction tx, {
    required String userId,
    required LedgerEffect? before,
    required LedgerEffect? after,
    required List<Budget> budgets,
  }) {
    _applyToAccounts(tx, userId: userId, before: before, after: after);
    _applyToRollups(tx, userId: userId, before: before, after: after);
    _applyToBudgets(
      tx,
      userId: userId,
      before: before,
      after: after,
      budgets: budgets,
    );
  }

  /// Reads the stored shape of a transaction into the form [apply] works with.
  ///
  /// Taken from the stored document rather than from a model the caller built, so
  /// an edit is measured against what is actually recorded.
  static LedgerEffect? effectOf(Json? data) => LedgerEffect.from(data);

  /// The effect a model will have once written, for a create.
  static LedgerEffect? effectOfModel(Transaction? transaction) {
    if (transaction == null) return null;
    return LedgerEffect(
      accountId: transaction.accountId,
      categoryId: transaction.categoryId,
      type: transaction.type,
      status: transaction.status,
      currency: transaction.amount.currency,
      amountMinor: transaction.amount.minorUnits.abs(),
      date: transaction.transactionDate,
      merchant: transaction.merchant,
      paymentMethod: transaction.paymentMethod?.wire,
      transferDirection: transaction.transferDirection,
    );
  }

  // -------------------------------------------------------------------------
  // Balances
  // -------------------------------------------------------------------------

  /// Moves the account balances.
  ///
  /// A transaction that changed account is two increments, not one: the old
  /// account gives the amount back and the new one takes it. A single increment on
  /// the new account would leave the old one permanently wrong.
  static void _applyToAccounts(
    fs.Transaction tx, {
    required String userId,
    required LedgerEffect? before,
    required LedgerEffect? after,
  }) {
    final previous = before != null && before.counts ? before : null;
    final current = after != null && after.counts ? after : null;

    final previousAccount = previous?.accountId;
    final currentAccount = current?.accountId;

    if (previousAccount != null && previousAccount != currentAccount) {
      tx.update(FirebaseService.accounts(userId).doc(previousAccount), {
        minorKey('current_balance'):
            FieldValue.increment(-previous!.signedMinor),
        ...updatedFields(),
      });
    }

    if (currentAccount != null) {
      final delta = previousAccount == currentAccount
          ? current!.signedMinor - previous!.signedMinor
          : current!.signedMinor;

      if (delta != 0) {
        tx.update(FirebaseService.accounts(userId).doc(currentAccount), {
          minorKey('current_balance'): FieldValue.increment(delta),
          ...updatedFields(),
        });
      }
    }
  }

  // -------------------------------------------------------------------------
  // Monthly rollups
  // -------------------------------------------------------------------------

  /// Keeps the rollup documents the analytics screens read.
  ///
  /// Without these, drawing a year's spending chart would mean reading every
  /// transaction in that year, on every visit — and Firestore's free tier is 50,000
  /// reads a day, which a few chart refreshes over a long history would eat into
  /// noticeably.
  ///
  /// Deltas are summed as plain numbers first. Two `FieldValue.increment` values
  /// cannot be added together, so an edit that keeps a transaction inside its month
  /// would otherwise apply the addition and drop the subtraction.
  static void _applyToRollups(
    fs.Transaction tx, {
    required String userId,
    required LedgerEffect? before,
    required LedgerEffect? after,
  }) {
    // Transfers move money between the user's own accounts. Counting them would
    // inflate income and expenses by the same amount and make a quiet month look
    // busy, so they are left out of the totals while still moving the balances.
    bool contributes(LedgerEffect? e) => e != null && e.counts && !e.type.isTransfer;

    final deltas = <String, Map<String, num>>{};
    final labels = <String, Map<String, Object?>>{};

    void record(LedgerEffect effect, int sign) {
      final month = FirebaseService.monthKey(effect.date);
      final numbers = deltas.putIfAbsent(month, () => <String, num>{});
      final plain = labels.putIfAbsent(month, () => <String, Object?>{});

      final amount = effect.amountMinor * sign;
      final isIncome = effect.type == TransactionType.income;
      final bucket = isIncome ? 'income' : 'expenses';
      final category = effect.categoryId ?? 'uncategorised';
      final day = effect.date.day.toString().padLeft(2, '0');

      void add(String path, num value) =>
          numbers[path] = (numbers[path] ?? 0) + value;

      add('transaction_count', sign);
      add(minorKey(bucket), amount);
      add('by_day.$day.${minorKey(bucket)}', amount);
      add('by_category.$category.${minorKey(isIncome ? 'income' : 'expense')}',
          amount);
      add('by_category.$category.count', sign);

      if (!isIncome) {
        final method = effect.paymentMethod ?? 'unspecified';
        add('by_payment_method.$method.${minorKey('total')}', amount);
        add('by_payment_method.$method.count', sign);

        final key = _merchantKey(effect.merchant);
        if (key != null) {
          add('by_merchant.$key.${minorKey('total')}', amount);
          add('by_merchant.$key.count', sign);
          if (sign == 1) {
            plain['by_merchant.$key.name'] = effect.merchant;
            plain['by_merchant.$key.last_date'] =
                Timestamp.fromDate(effect.date);
          }
        }
      }

      plain['currency'] = effect.currency;
    }

    if (contributes(before)) record(before!, -1);
    if (contributes(after)) record(after!, 1);

    for (final entry in deltas.entries) {
      final payload = <String, dynamic>{
        'month': entry.key,
        'user_id': userId,
        ...updatedFields(),
      };

      for (final delta in entry.value.entries) {
        // A net delta of zero means the two sides cancelled: nothing to write.
        if (delta.value == 0) continue;
        _assign(payload, delta.key, FieldValue.increment(delta.value));
      }

      for (final label in (labels[entry.key] ?? const {}).entries) {
        _assign(payload, label.key, label.value);
      }

      tx.set(
        FirebaseService.monthlySummaries(userId).doc(entry.key),
        payload,
        SetOptions(merge: true),
      );
    }

    // The largest expense is a maximum, not a sum, so it cannot be an increment.
    // It is replaced only when a new expense beats the stored one, which means
    // deleting the record-holder leaves a stale id — the client reads that
    // transaction by id and shows nothing when it is gone. Recomputing the true
    // maximum on a delete would mean scanning the month, which is the cost the
    // rollups exist to avoid.
    if (contributes(after) && after!.type == TransactionType.expense) {
      tx.set(
        FirebaseService.monthlySummaries(userId)
            .doc(FirebaseService.monthKey(after.date)),
        {
          'largest_expense_candidate': {
            minorKey('amount'): after.amountMinor,
            'currency': after.currency,
            'merchant': after.merchant,
            'date': Timestamp.fromDate(after.date),
          },
        },
        SetOptions(merge: true),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Budgets
  // -------------------------------------------------------------------------

  /// Keeps each budget's spend figure for the period it belongs to.
  ///
  /// When the period has rolled over, the stored figure is the previous period's
  /// and is replaced rather than incremented. The client reads a figure stamped
  /// with an older period start as zero, so the two agree either way.
  static void _applyToBudgets(
    fs.Transaction tx, {
    required String userId,
    required LedgerEffect? before,
    required LedgerEffect? after,
    required List<Budget> budgets,
  }) {
    LedgerEffect? expenseOf(LedgerEffect? e) =>
        e != null && e.counts && e.type == TransactionType.expense ? e : null;

    final removed = expenseOf(before);
    final added = expenseOf(after);
    if (removed == null && added == null) return;
    if (budgets.isEmpty) return;

    final reference = (added ?? removed)!.date;

    for (final budget in budgets) {
      if (budget.isArchived) continue;

      final period = budget.currentRange(reference);

      bool applies(LedgerEffect? e) =>
          e != null &&
          (budget.categoryId == null || budget.categoryId == e.categoryId);

      bool inPeriod(LedgerEffect? e) =>
          e != null &&
          !e.date.isBefore(period.start) &&
          !e.date.isAfter(period.end);

      var delta = 0;
      if (applies(removed) && inPeriod(removed)) delta -= removed!.amountMinor;
      if (applies(added) && inPeriod(added)) delta += added!.amountMinor;
      if (delta == 0) continue;

      final storedStart = budget.spentPeriodStart;
      final samePeriod = storedStart != null &&
          AppDateUtils.isSameDay(storedStart, period.start);

      final ref = FirebaseService.budgets(userId).doc(budget.id);

      if (samePeriod) {
        tx.update(ref, {
          minorKey('spent'): FieldValue.increment(delta),
          ...updatedFields(),
        });
      } else {
        // A new period: the stored figure belongs to the last one, so it is
        // replaced rather than added to.
        tx.update(ref, {
          minorKey('spent'): delta < 0 ? 0 : delta,
          'spent_period_start': Timestamp.fromDate(period.start),
          ...updatedFields(),
        });
      }
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Writes a value at a dotted path, creating the intermediate maps.
  ///
  /// `set` does not read a dot in a key as a path — it would store a field whose
  /// name contains a dot — so the nesting has to be built explicitly.
  static void _assign(Map<String, dynamic> target, String path, Object? value) {
    final parts = path.split('.');
    var cursor = target;

    for (var i = 0; i < parts.length - 1; i++) {
      final key = parts[i];
      final existing = cursor[key];
      if (existing is! Map<String, dynamic>) {
        cursor[key] = <String, dynamic>{};
      }
      cursor = cursor[key] as Map<String, dynamic>;
    }

    cursor[parts.last] = value;
  }

  /// A map key for a merchant name.
  ///
  /// Firestore map keys may not contain a dot, and a name read off a receipt by OCR
  /// can contain anything at all. Truncated as well, because the key is part of the
  /// document and a month of long names would push it towards the 1 MB limit.
  static String? _merchantKey(String? merchant) {
    final normalised = merchant?.toLowerCase().trim();
    if (normalised == null || normalised.isEmpty) return null;
    final key = normalised
        .replaceAll(RegExp(r'[^a-z0-9 _-]'), '_')
        .trim();
    if (key.isEmpty) return null;
    return key.length <= 60 ? key : key.substring(0, 60);
  }
}

/// The parts of a transaction that affect a derived figure.
///
/// Built either from a stored document — which is what an edit is measured
/// against — or from a model about to be written.
class LedgerEffect {
  const LedgerEffect({
    required this.accountId,
    required this.categoryId,
    required this.type,
    required this.status,
    required this.currency,
    required this.amountMinor,
    required this.date,
    required this.merchant,
    required this.paymentMethod,
    required this.transferDirection,
  });

  final String accountId;
  final String? categoryId;
  final TransactionType type;
  final TransactionStatus status;
  final String currency;
  final int amountMinor;
  final DateTime date;
  final String? merchant;
  final String? paymentMethod;
  final TransferDirection? transferDirection;

  static LedgerEffect? from(Json? data) {
    if (data == null) return null;
    final accountId = data.strOrNull('account_id');
    if (accountId == null) return null;

    return LedgerEffect(
      accountId: accountId,
      categoryId: data.strOrNull('category_id'),
      type: TransactionType.fromWire(data.strOrNull('type')),
      status: TransactionStatus.fromWire(data.strOrNull('status')),
      currency: data.str('currency', fallback: 'LKR'),
      amountMinor: data.intVal(minorKey('amount')).abs(),
      date: data.dateVal('transaction_date'),
      merchant: data.strOrNull('merchant'),
      paymentMethod: data.strOrNull('payment_method'),
      transferDirection:
          TransferDirection.fromWire(data.strOrNull('transfer_direction')),
    );
  }

  /// Whether this transaction should move balances and totals.
  ///
  /// A pending transaction has not happened yet — it is a draft, or a figure an
  /// import has proposed — so counting it would show money the account does not
  /// have.
  bool get counts => status == TransactionStatus.confirmed;

  /// The signed effect on the account's balance.
  ///
  /// The stored amount is always positive; the sign comes from the type, and for a
  /// transfer from which leg this is. A document therefore cannot contradict itself
  /// by being a negative expense.
  int get signedMinor => switch (type) {
        TransactionType.income => amountMinor,
        TransactionType.expense => -amountMinor,
        TransactionType.transfer =>
          transferDirection == TransferDirection.incoming
              ? amountMinor
              : -amountMinor,
      };
}
