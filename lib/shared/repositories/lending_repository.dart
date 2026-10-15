import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;

import '../../core/constants/enums.dart';
import '../../core/errors/app_exception.dart';
import '../../core/services/firebase_service.dart';
import '../../core/utils/money.dart';
import '../models/json_map.dart';
import '../models/lending.dart';
import '../models/transaction.dart';
import 'base_repository.dart';

/// Money lent to, or borrowed from, someone who is not tracked as an account
/// of their own — at `users/{uid}/lendings`.
///
/// Every movement is also a transaction: the principal when the record is
/// created, and each repayment after. Both are written as `TRANSFER`-typed
/// transactions carrying this record's id and no peer account, which is what
/// keeps the money off the user's income/expense totals while still moving
/// their account balance — the same trick a transfer between two of the
/// user's own accounts already relies on, since every rollup and budget in
/// `LedgerWriter` already excludes transfers.
class LendingRepository extends BaseRepository {
  LendingRepository({super.firestore});

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseService.lendings(userId);

  Future<List<LendingRecord>> fetchAll({bool includeSettled = true}) async {
    final records = await fetchList(
      _col.orderBy('created_at', descending: true),
      LendingRecord.fromJson,
    );
    if (includeSettled) return records;
    return records.where((r) => !r.isSettled).toList(growable: false);
  }

  Stream<List<LendingRecord>> watchAll() => watchList(
        _col.orderBy('created_at', descending: true),
        LendingRecord.fromJson,
      );

  Future<LendingRecord> fetchById(String id) =>
      fetchDoc(_col.doc(id), LendingRecord.fromJson);

  /// Creates a lending record and posts its principal as a transaction.
  Future<LendingRecord> create({
    required String personName,
    required LendingKind kind,
    required Money principal,
    required String accountId,
    DateTime? date,
    String? notes,
    DateTime? dueDate,
  }) =>
      guard(() async {
        final name = personName.trim();
        if (name.isEmpty) {
          throw const ValidationException('Enter who this is with.');
        }
        if (principal.isZero || principal.isNegative) {
          throw const ValidationException(
            'The amount must be greater than zero.',
          );
        }

        final occurredOn = date ?? DateTime.now();
        final ref = _col.doc();
        final txRef = FirebaseService.transactions(userId).doc();

        // You handed the money over when you lent it; you received it when
        // you borrowed — the same direction the principal's leg takes.
        final direction = kind.isReceivable
            ? TransferDirection.out
            : TransferDirection.incoming;

        await db.runTransaction((tx) async {
          final account =
              await tx.get(FirebaseService.accounts(userId).doc(accountId));
          if (!account.exists) throw const NotFoundException();

          tx.set(ref, {
            'person_name': name,
            'kind': kind.wire,
            ...moneyFields('principal', principal),
            ...moneyFields('outstanding', principal, withCurrency: false),
            'account_id': accountId,
            'notes': notes,
            'due_date': dueDate == null ? null : dateOnly(dueDate),
            'user_id': userId,
            ...createdFields(),
          });

          tx.set(txRef, {
            'user_id': userId,
            'account_id': accountId,
            'category_id': null,
            'type': TransactionType.transfer.wire,
            ...moneyFields('amount', principal),
            'description':
                kind.isReceivable ? 'Lent to $name' : 'Borrowed from $name',
            'merchant': null,
            'payment_method': null,
            'transaction_date': Timestamp.fromDate(occurredOn),
            'notes': notes,
            'document_id': null,
            'source': TransactionSource.manual.wire,
            'status': TransactionStatus.confirmed.wire,
            'transfer_group_id': null,
            'transfer_direction': direction.wire,
            'transfer_peer_account_id': null,
            'lending_id': ref.id,
            'is_split': false,
            'search_terms': searchTerms([name, notes]),
            ...createdFields(),
          });

          tx.update(FirebaseService.accounts(userId).doc(accountId), {
            minorKey('current_balance'): FieldValue.increment(
              direction == TransferDirection.incoming
                  ? principal.minorUnits
                  : -principal.minorUnits,
            ),
            ...updatedFields(),
          });
        });

        return fetchById(ref.id);
      });

  /// Records a repayment: reduces the outstanding balance and posts the
  /// money moving the other way.
  Future<void> recordRepayment({
    required LendingRecord lending,
    required Money amount,
    DateTime? date,
    String? notes,
    String? accountId,
  }) =>
      guard(() async {
        if (amount.isZero || amount.isNegative) {
          throw const ValidationException(
            'Enter an amount greater than zero.',
          );
        }
        if (lending.isSettled) {
          throw const ValidationException('This is already fully settled.');
        }

        // Repaid money does not have to land back in the same account the
        // principal left from — the friend might hand over cash instead of a
        // bank transfer, say. Defaults to the original account when the
        // caller does not choose one.
        final targetAccountId = accountId ?? lending.accountId;

        final occurredOn = date ?? DateTime.now();
        final txRef = FirebaseService.transactions(userId).doc();
        final lendingRef = _col.doc(lending.id);
        final accountRef = FirebaseService.accounts(userId).doc(targetAccountId);

        // Being paid back moves money in; paying back what you borrowed moves
        // it out — the opposite of the principal's own direction.
        final direction = lending.kind.isReceivable
            ? TransferDirection.incoming
            : TransferDirection.out;

        await db.runTransaction((tx) async {
          final snapshot = await tx.get(lendingRef);
          if (!snapshot.exists) throw const NotFoundException();

          final account = await tx.get(accountRef);
          if (!account.exists) throw const NotFoundException();

          final accountCurrency =
              account.asJson.str('currency', fallback: amount.currency);
          if (accountCurrency != amount.currency) {
            throw ValidationException(
              'That account holds $accountCurrency. Choose an account in '
              '${amount.currency} instead.',
            );
          }

          final outstanding = snapshot.asJson.money('outstanding');
          if (amount > outstanding) {
            throw ValidationException(
              'At most ${outstanding.format()} is still outstanding.',
            );
          }

          tx.update(lendingRef, {
            minorKey('outstanding'): (outstanding - amount).minorUnits,
            ...updatedFields(),
          });

          tx.set(txRef, {
            'user_id': userId,
            'account_id': targetAccountId,
            'category_id': null,
            'type': TransactionType.transfer.wire,
            ...moneyFields('amount', amount),
            'description': lending.kind.isReceivable
                ? 'Repaid by ${lending.personName}'
                : 'Repaid to ${lending.personName}',
            'merchant': null,
            'payment_method': null,
            'transaction_date': Timestamp.fromDate(occurredOn),
            'notes': notes,
            'document_id': null,
            'source': TransactionSource.manual.wire,
            'status': TransactionStatus.confirmed.wire,
            'transfer_group_id': null,
            'transfer_direction': direction.wire,
            'transfer_peer_account_id': null,
            'lending_id': lending.id,
            'is_split': false,
            'search_terms': searchTerms([lending.personName, notes]),
            ...createdFields(),
          });

          tx.update(accountRef, {
            minorKey('current_balance'): FieldValue.increment(
              direction == TransferDirection.incoming
                  ? amount.minorUnits
                  : -amount.minorUnits,
            ),
            ...updatedFields(),
          });
        });
      });

  /// Edits the name, note or due date. The principal, the account and who
  /// owes whom are fixed once a real transaction has moved against them.
  Future<LendingRecord> update(LendingRecord lending) => guard(() async {
        await _col.doc(lending.id).update({
          ...lending.toUpdateJson(),
          ...updatedFields(),
        });
        return fetchById(lending.id);
      });

  /// Every transaction this record produced, most recent first.
  Future<List<Transaction>> fetchHistory(String lendingId) => fetchList(
        FirebaseService.transactions(userId)
            .where('lending_id', isEqualTo: lendingId)
            .orderBy('transaction_date', descending: true),
        Transaction.fromJson,
      );

  /// Deletes a lending record and every transaction it produced, reversing
  /// each one's balance effect.
  ///
  /// Mirrors why an account with transactions must be archived rather than
  /// deleted: once real money has moved, erasing the record silently would
  /// leave the account balance wrong. Deleting here is an explicit undo, not a
  /// tidy-up, so every leg is reversed rather than left behind.
  Future<void> delete(String id) => guard(() async {
        final history = await FirebaseService.transactions(userId)
            .where('lending_id', isEqualTo: id)
            .get();

        await db.runTransaction((tx) async {
          for (final doc in history.docs) {
            final data = doc.asJson;
            final accountId = data.strOrNull('account_id');
            if (accountId == null) continue;

            final direction = TransferDirection.fromWire(
              data.strOrNull('transfer_direction'),
            );
            final amount = data.money('amount');
            final signedMinor = direction == TransferDirection.incoming
                ? amount.minorUnits
                : -amount.minorUnits;

            tx.delete(doc.reference);
            tx.update(FirebaseService.accounts(userId).doc(accountId), {
              minorKey('current_balance'): FieldValue.increment(-signedMinor),
              ...updatedFields(),
            });
          }
          tx.delete(_col.doc(id));
        });
      });
}
