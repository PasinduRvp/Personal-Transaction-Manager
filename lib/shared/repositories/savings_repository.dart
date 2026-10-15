import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/errors/app_exception.dart';
import '../../core/services/firebase_service.dart';
import '../../core/utils/money.dart';
import '../../core/constants/enums.dart';
import '../models/json_map.dart';
import '../models/savings_goal.dart';
import 'base_repository.dart';

/// Savings goals at `users/{uid}/savingsGoals`, with contributions in a
/// `contributions` subcollection under each.
///
/// A goal's `current_amount_minor` is the sum of its contributions, maintained by
/// the `onContributionWritten` trigger. The client never writes it: two devices
/// adding to the same goal at once would otherwise each compute the total from
/// its own stale copy and the later write would discard the earlier deposit.
class SavingsRepository extends BaseRepository {
  SavingsRepository({super.firestore});

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseService.savingsGoals(userId);

  CollectionReference<Map<String, dynamic>> _contributions(String goalId) =>
      FirebaseService.contributions(goalId, userId);

  Future<List<SavingsGoal>> fetchAll({bool includeArchived = false}) {
    final query = includeArchived
        ? _col.orderBy('is_completed').orderBy('created_at')
        : _col
            .where('is_archived', isEqualTo: false)
            .orderBy('is_completed')
            .orderBy('created_at');
    return fetchList(query, SavingsGoal.fromJson);
  }

  Future<SavingsGoal> fetchById(String id) =>
      fetchDoc(_col.doc(id), SavingsGoal.fromJson);

  Future<SavingsGoal> create(SavingsGoal goal) => guard(() async {
        final ref = _col.doc();
        await ref.set({
          ...goal.toInsertJson(),
          'user_id': userId,
          // Derived; seeded at zero and only the trigger moves it afterwards.
          minorKey('current_amount'): 0,
          'is_completed': false,
          ...createdFields(),
        });
        return fetchById(ref.id);
      });

  Future<SavingsGoal> update(SavingsGoal goal) => guard(() async {
        await _col.doc(goal.id).update({
          ...goal.toUpdateJson(),
          ...updatedFields(),
        });
        return fetchById(goal.id);
      });

  Future<SavingsGoal> setArchived(String id, {required bool archived}) =>
      guard(() async {
        await _col.doc(id).update({
          'is_archived': archived,
          ...updatedFields(),
        });
        return fetchById(id);
      });

  /// Deletes a goal and its contribution history.
  ///
  /// Any transfers the contributions produced stay in the ledger: the money
  /// really did move between accounts, and erasing that to tidy up a goal would
  /// falsify the user's balances.
  ///
  /// Firestore does not delete a subcollection with its parent, so the
  /// contributions are removed explicitly — otherwise they would linger as
  /// unreachable documents that still count against storage.
  Future<void> delete(String id) => guard(() async {
        while (true) {
          final page = await _contributions(id).limit(400).get();
          if (page.docs.isEmpty) break;

          final batch = db.batch();
          for (final doc in page.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();

          if (page.docs.length < 400) break;
        }
        await _col.doc(id).delete();
      });

  Future<List<SavingsContribution>> fetchContributions(String goalId) =>
      fetchList(
        _contributions(goalId)
            .orderBy('occurred_on', descending: true)
            .orderBy('created_at', descending: true),
        SavingsContribution.fromJson,
      );

  /// Adds to a goal.
  ///
  /// Goes through the `contributeToGoal` callable because it is up to four writes
  /// — the contribution, the goal total, and both legs of a transfer when
  /// [fromAccountId] is given — and they have to succeed or fail together. A
  /// client-side version that lost connectivity between the contribution and the
  /// transfer would leave the goal claiming money the accounts never gave up.
  /// Adds to a goal.
  ///
  /// Up to four documents change together — the contribution, the goal's total, and
  /// both legs of a transfer when the deposit is funded from an account — so it runs
  /// as one Firestore transaction. A version that lost connectivity partway would
  /// leave the goal claiming money the accounts never gave up.
  Future<void> contribute({
    required SavingsGoal goal,
    required Money amount,
    DateTime? occurredOn,
    String? note,
    String? fromAccountId,
  }) =>
      guard(() async {
        if (amount.isZero) {
          throw const ValidationException('Enter an amount to add.');
        }
        if (amount.isNegative) {
          throw const ValidationException(
            'Use the withdraw option to take money out of a goal.',
          );
        }
        await _record(
          goal: goal,
          amount: amount,
          occurredOn: occurredOn ?? DateTime.now(),
          note: note,
          accountId: fromAccountId,
        );
      });

  /// Takes money out of a goal, stored as a negative contribution so the goal's
  /// history reads as a single ledger rather than two lists to reconcile.
  Future<void> withdraw({
    required SavingsGoal goal,
    required Money amount,
    DateTime? occurredOn,
    String? note,
    String? toAccountId,
  }) =>
      guard(() async {
        if (amount.isZero || amount.isNegative) {
          throw const ValidationException(
            'Enter an amount greater than zero to withdraw.',
          );
        }
        if (amount > goal.currentAmount) {
          throw ValidationException(
            'You can withdraw at most ${goal.currentAmount.format()} from this '
            'goal.',
          );
        }
        await _record(
          goal: goal,
          amount: -amount,
          occurredOn: occurredOn ?? DateTime.now(),
          note: note,
          accountId: toAccountId,
        );
      });

  /// Writes a contribution and everything that must move with it.
  ///
  /// The goal's total moves by `FieldValue.increment` rather than being read and
  /// written back, so two devices depositing at once both land instead of the later
  /// write erasing the earlier deposit.
  Future<void> _record({
    required SavingsGoal goal,
    required Money amount,
    required DateTime occurredOn,
    required String? note,
    required String? accountId,
  }) async {
    final goalRef = _col.doc(goal.id);
    final contributionRef = _contributions(goal.id).doc();
    final isDeposit = amount.isPositive;

    await db.runTransaction((tx) async {
      final snapshot = await tx.get(goalRef);
      if (!snapshot.exists) throw const NotFoundException();

      final data = snapshot.asJson;
      final goalCurrency = data.str('currency', fallback: amount.currency);

      if (goalCurrency != amount.currency) {
        throw ValidationException(
          'That goal is in $goalCurrency. Enter the amount in $goalCurrency.',
        );
      }

      if (!isDeposit) {
        final current = data.money('current_amount');
        if (amount.abs > current) {
          throw const ValidationException(
            'You cannot withdraw more than this goal holds.',
          );
        }
      }

      final goalAccountId = data.strOrNull('account_id');
      final linkedAccountId = accountId ?? goalAccountId;

      // A real transfer is recorded only when the money actually moves between two
      // different accounts. Without one the contribution is a note against the goal,
      // which is the right behaviour for someone setting cash aside.
      final movesMoney = linkedAccountId != null &&
          goalAccountId != null &&
          linkedAccountId != goalAccountId;

      final groupId = movesMoney
          ? FirebaseService.transactions(userId).doc().id
          : null;

      tx.set(contributionRef, {
        'user_id': userId,
        'goal_id': goal.id,
        ...moneyFields('amount', amount),
        'occurred_on': dateOnly(occurredOn),
        'note': note,
        'account_id': linkedAccountId,
        'transfer_group_id': groupId,
        ...createdFields(),
      });

      tx.update(goalRef, {
        minorKey('current_amount'): FieldValue.increment(amount.minorUnits),
        ...updatedFields(),
      });

      if (!movesMoney || groupId == null) return;

      final from = isDeposit ? linkedAccountId : goalAccountId;
      final to = isDeposit ? goalAccountId : linkedAccountId;
      final magnitude = amount.abs;
      final goalName = data.str('name', fallback: 'savings goal');

      for (final leg in [
        (direction: TransferDirection.out, account: from, peer: to),
        (direction: TransferDirection.incoming, account: to, peer: from),
      ]) {
        tx.set(FirebaseService.transactions(userId).doc(), {
          'user_id': userId,
          'account_id': leg.account,
          'category_id': null,
          'type': TransactionType.transfer.wire,
          ...moneyFields('amount', magnitude),
          'description': isDeposit
              ? 'Saved towards $goalName'
              : 'Withdrawn from $goalName',
          'merchant': null,
          'payment_method': null,
          'transaction_date': Timestamp.fromDate(occurredOn),
          'notes': note,
          'document_id': null,
          'source': TransactionSource.manual.wire,
          'status': TransactionStatus.confirmed.wire,
          'transfer_group_id': groupId,
          'transfer_direction': leg.direction.wire,
          'transfer_peer_account_id': leg.peer,
          'savings_goal_id': goal.id,
          'is_split': false,
          'search_terms': searchTerms([goalName, note]),
          ...createdFields(),
        });

        tx.update(FirebaseService.accounts(userId).doc(leg.account), {
          minorKey('current_balance'): FieldValue.increment(
            leg.direction == TransferDirection.incoming
                ? magnitude.minorUnits
                : -magnitude.minorUnits,
          ),
          ...updatedFields(),
        });
      }
    });
  }

  /// Removes a contribution, adjusting the goal's total to match.
  Future<void> deleteContribution({
    required String goalId,
    required String contributionId,
  }) =>
      guard(() async {
        final ref = _contributions(goalId).doc(contributionId);

        await db.runTransaction((tx) async {
          final snapshot = await tx.get(ref);
          if (!snapshot.exists) return;

          final amount = snapshot.asJson.money('amount');
          tx.delete(ref);

          // The goal's total is the sum of its contributions, so removing one has
          // to take it back out. Any transfer the contribution produced is left
          // alone: the money really did move between accounts, and erasing that to
          // tidy up a goal would falsify the user's balances.
          tx.update(_col.doc(goalId), {
            minorKey('current_amount'):
                FieldValue.increment(-amount.minorUnits),
            ...updatedFields(),
          });
        });
      });

  /// Marks a goal complete even if the target was not fully reached — the user
  /// may have bought the thing at a discount.
  ///
  /// `is_completed` is one of the few flags on this document a client may set:
  /// it is the user's judgement, not a derived figure.
  Future<SavingsGoal> markComplete(String id) => guard(() async {
        await _col.doc(id).update({
          'is_completed': true,
          'completed_at': FieldValue.serverTimestamp(),
          ...updatedFields(),
        });
        return fetchById(id);
      });
}
