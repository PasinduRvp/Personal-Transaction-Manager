import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/enums.dart';
import '../../core/services/firebase_service.dart';
import '../models/budget.dart';
import '../models/json_map.dart';
import '../models/profile.dart';
import 'base_repository.dart';

/// Raises the budget notifications that a Cloud Function used to raise.
///
/// On the paid plan a Firestore trigger watched each budget's spend figure and
/// wrote an alert when it crossed a threshold. There is no trigger here, so the
/// sweep runs on the client after a transaction has been written and the spend
/// figures have moved.
///
/// Two things make that safe to repeat. The levels already raised are recorded
/// **on the budget document**, not inferred from which notifications still
/// exist — so swiping an alert away does not cause the next transaction to
/// raise it again. And the record is stamped with the period it belongs to, so
/// a new month starts clean without anything having to clear it.
class BudgetAlertService extends BaseRepository {
  BudgetAlertService({super.firestore});

  /// Raises every threshold newly crossed, and returns how many it wrote.
  ///
  /// Never throws: this runs after a transaction has already been saved, and a
  /// notification that could not be written is not a reason to tell the user
  /// their transaction failed. Failures are logged and the sweep gives up until
  /// the next write.
  Future<int> sweep({
    required List<BudgetProgress> progress,
    required UserSettings settings,
  }) async {
    try {
      return await _sweep(progress: progress, settings: settings);
    } on Object catch (error, stack) {
      log.warning('Budget alert sweep failed', error, stack);
      return 0;
    }
  }

  Future<int> _sweep({
    required List<BudgetProgress> progress,
    required UserSettings settings,
  }) async {
    final batch = db.batch();

    /// Notifications actually raised, which is what the caller cares about.
    var written = 0;

    /// Everything queued, including the budget updates that record a muted
    /// level as raised. Committing is decided on this, not on [written].
    var queued = 0;

    for (final item in progress) {
      if (item.budget.isArchived) continue;

      // A limit of zero would make every percentage infinite, and a budget
      // nothing has been spent against has crossed nothing.
      if (item.limit.isZero || item.spent.isZero) continue;

      final pending = item.pendingAlerts;
      if (pending.isEmpty) continue;

      // The levels the user has switched off are still recorded as raised.
      // Otherwise turning the setting back on next week would deliver a stale
      // "you reached 75%" for a threshold crossed days ago.
      final announced =
          pending.where((level) => settings.isEnabled(level.kind)).toList();

      for (final level in announced) {
        batch.set(
          FirebaseService.notifications(userId).doc(_idFor(item, level)),
          _payloadFor(item, level),
        );
        written++;
        queued++;
      }

      batch.update(FirebaseService.budgets(userId).doc(item.budget.id), {
        'alerted_period_start': Timestamp.fromDate(item.range.start),
        // Rewritten whole rather than appended to with `arrayUnion`, because a
        // period rollover has to *replace* the previous period's set, and the
        // model has already worked out which of those still apply.
        'alerted_levels': <String>{
          if (item.hasAlertStateForPeriod) ...item.budget.alertedLevels,
          ...pending.map((level) => level.wire),
        }.toList(),
        ...updatedFields(),
      });
      queued++;
    }

    // A muted level still produces a budget update and no notification, so the
    // decision to commit cannot be made on [written] alone.
    if (queued == 0) return 0;

    await batch.commit();
    return written;
  }

  /// A derived id, so the same alert written twice is the same document rather
  /// than a duplicate row in the user's list.
  ///
  /// One consequence worth knowing: the rules only allow a notification's
  /// `is_read` and `read_at` to be changed after creation, so writing this id
  /// a second time is rejected rather than silently resetting an alert the
  /// user has already read. That can only happen when two devices sweep the
  /// same crossing at once, and the loser's batch fails as a whole — which is
  /// the right outcome, because the alert it was trying to raise now exists.
  String _idFor(BudgetProgress item, BudgetAlertLevel level) {
    final period = dateOnly(item.range.start);
    return 'budget_${item.budget.id}_${period}_${level.wire}';
  }

  Json _payloadFor(BudgetProgress item, BudgetAlertLevel level) {
    final name = item.budget.displayName;
    final percent = item.percentUsed.round();

    final (title, body) = switch (level) {
      BudgetAlertLevel.threeQuarters => (
          '$name is three-quarters spent',
          'You have used $percent% of your ${item.limit.format()} budget. '
              '${item.remaining.format()} left for '
              '${_daysPhrase(item.daysRemaining)}.',
        ),
      BudgetAlertLevel.ninety => (
          '$name is nearly spent',
          'You have used $percent% of your ${item.limit.format()} budget. '
              'Only ${item.remaining.format()} left for '
              '${_daysPhrase(item.daysRemaining)}.',
        ),
      BudgetAlertLevel.spent => (
          '$name is fully spent',
          'You have used the whole ${item.limit.format()} budget with '
              '${_daysPhrase(item.daysRemaining)} to go.',
        ),
      BudgetAlertLevel.overspent => (
          '$name is over budget',
          'You are ${item.overspend.format()} over your '
              '${item.limit.format()} budget — $percent% of the limit.',
        ),
    };

    return <String, dynamic>{
      'user_id': userId,
      'kind': level.kind.wire,
      'title': title,
      'body': body,
      'is_read': false,
      'read_at': null,
      'entity_type': 'budget',
      'entity_id': item.budget.id,
      'payload': <String, dynamic>{
        'level': level.wire,
        'percent_used': percent,
        ...moneyFields('limit', item.limit),
        ...moneyFields('spent', item.spent, withCurrency: false),
      },
      ...createdFields(),
    };
  }

  /// "3 days left" reads better than "3 days remaining in the period", and the
  /// last day of a period should not say "0 days".
  static String _daysPhrase(int days) => switch (days) {
        <= 0 => 'the rest of the period',
        1 => '1 day',
        _ => '$days days',
      };
}
