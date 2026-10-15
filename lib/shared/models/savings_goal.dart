import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/money.dart';
import 'json_map.dart';

/// A row of `public.savings_goals`.
///
/// [currentAmount] is maintained by a database trigger that sums
/// `savings_contributions`, so contributions and withdrawals can never drift
/// out of step with the stored total.
class SavingsGoal extends Equatable {
  const SavingsGoal({
    required this.id,
    required this.userId,
    required this.name,
    required this.targetAmount,
    required this.currentAmount,
    this.targetDate,
    this.accountId,
    this.iconName,
    this.colorHex,
    this.notes,
    this.isCompleted = false,
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String name;
  final Money targetAmount;
  final Money currentAmount;
  final DateTime? targetDate;

  /// Optional account the money physically lives in.
  final String? accountId;
  final String? iconName;
  final String? colorHex;
  final String? notes;
  final bool isCompleted;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The goal's currency. Held on the amounts rather than duplicated as its own
  /// field, so the two can never disagree.
  String get currency => targetAmount.currency;

  Color get color =>
      AppColors.tryParseHex(colorHex) ?? AppColors.deterministic(id);

  IconData get icon => iconFor(iconName);

  /// Resolves an icon name without needing a goal instance, so a form can
  /// preview the choice before the goal exists.
  static IconData iconFor(String? name) =>
      _iconCatalogue[name?.toLowerCase()] ?? Icons.savings_outlined;

  static const Map<String, IconData> _iconCatalogue = {
    'laptop': Icons.laptop_mac_outlined,
    'phone': Icons.smartphone_outlined,
    'car': Icons.directions_car_outlined,
    'house': Icons.house_outlined,
    'travel': Icons.flight_takeoff_outlined,
    'education': Icons.school_outlined,
    'wedding': Icons.favorite_outline,
    'emergency': Icons.health_and_safety_outlined,
    'gift': Icons.card_giftcard_outlined,
    'camera': Icons.camera_alt_outlined,
    'bike': Icons.pedal_bike_outlined,
    'savings': Icons.savings_outlined,
  };

  static List<String> get iconNames => _iconCatalogue.keys.toList();

  /// 0–100, clamped. A goal can be over-funded; the bar stops at 100.
  double get progressPercent =>
      currentAmount.percentOf(targetAmount).clamp(0, 100);

  double get progressFraction => (progressPercent / 100).clamp(0.0, 1.0);

  Money get remaining {
    final diff = targetAmount - currentAmount;
    return diff.isNegative ? Money.zero(targetAmount.currency) : diff;
  }

  bool get isReached => currentAmount >= targetAmount;

  int? get daysRemaining {
    final target = targetDate;
    if (target == null) return null;
    final today = AppDateUtils.startOfDay(DateTime.now());
    return AppDateUtils.startOfDay(target).difference(today).inDays;
  }

  bool get isOverdue {
    final days = daysRemaining;
    return days != null && days < 0 && !isReached;
  }

  /// How much must be set aside each month to hit the target date.
  /// Null when there is no target date or the goal is already reached.
  Money? get requiredMonthlyContribution {
    final days = daysRemaining;
    if (days == null || isReached) return null;
    if (days <= 0) return remaining;
    final months = days / 30.4375;
    return remaining * (1 / (months < 1 ? 1 : months));
  }

  factory SavingsGoal.fromJson(Json json) => SavingsGoal(
        id: json.str('id'),
        userId: json.str('user_id'),
        name: json.str('name'),
        targetAmount: json.money('target_amount'),
        currentAmount: json.money('current_amount'),
        targetDate: json.dateOrNull('target_date'),
        accountId: json.strOrNull('account_id'),
        iconName: json.strOrNull('icon'),
        colorHex: json.strOrNull('color'),
        notes: json.strOrNull('notes'),
        isCompleted: json.boolVal('is_completed'),
        isArchived: json.boolVal('is_archived'),
        createdAt: json.dateVal('created_at'),
        updatedAt: json.dateVal('updated_at'),
      );

  Json toInsertJson() => compactJson({
        'name': name,
        ...moneyFields('target_amount', targetAmount),
        'target_date': targetDate == null ? null : dateOnly(targetDate!),
        'account_id': accountId,
        'icon': iconName,
        'color': colorHex,
        'notes': notes,
      });

  Json toUpdateJson() => compactJson({
        'name': name,
        ...moneyFields('target_amount', targetAmount, withCurrency: false),
        'target_date':
            targetDate == null ? Patch.clear : dateOnly(targetDate!),
        'account_id': accountId ?? Patch.clear,
        'icon': iconName ?? Patch.clear,
        'color': colorHex ?? Patch.clear,
        'notes': notes ?? Patch.clear,
        'is_completed': isCompleted,
        'is_archived': isArchived,
      });

  SavingsGoal copyWith({
    String? name,
    Money? targetAmount,
    Money? currentAmount,
    Object? targetDate = _sentinel,
    Object? accountId = _sentinel,
    Object? iconName = _sentinel,
    Object? colorHex = _sentinel,
    Object? notes = _sentinel,
    bool? isCompleted,
    bool? isArchived,
  }) =>
      SavingsGoal(
        id: id,
        userId: userId,
        name: name ?? this.name,
        targetAmount: targetAmount ?? this.targetAmount,
        currentAmount: currentAmount ?? this.currentAmount,
        targetDate:
            targetDate == _sentinel ? this.targetDate : targetDate as DateTime?,
        accountId:
            accountId == _sentinel ? this.accountId : accountId as String?,
        iconName: iconName == _sentinel ? this.iconName : iconName as String?,
        colorHex: colorHex == _sentinel ? this.colorHex : colorHex as String?,
        notes: notes == _sentinel ? this.notes : notes as String?,
        isCompleted: isCompleted ?? this.isCompleted,
        isArchived: isArchived ?? this.isArchived,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  static const Object _sentinel = Object();

  @override
  List<Object?> get props => [
        id,
        name,
        targetAmount,
        currentAmount,
        targetDate,
        accountId,
        iconName,
        colorHex,
        notes,
        isCompleted,
        isArchived,
      ];
}

/// A row of `public.savings_contributions`. A withdrawal is stored as a
/// negative amount so the goal's history reads as a single ledger.
class SavingsContribution extends Equatable {
  const SavingsContribution({
    required this.id,
    required this.goalId,
    required this.amount,
    required this.occurredOn,
    this.note,
    this.transactionId,
    required this.createdAt,
  });

  final String id;
  final String goalId;

  /// Positive for a contribution, negative for a withdrawal.
  final Money amount;
  final DateTime occurredOn;
  final String? note;

  /// Set when the contribution also produced a transfer transaction.
  final String? transactionId;
  final DateTime createdAt;

  bool get isWithdrawal => amount.isNegative;

  factory SavingsContribution.fromJson(Json json) => SavingsContribution(
        id: json.str('id'),
        goalId: json.str('goal_id'),
        amount: json.money('amount'),
        occurredOn: json.dateVal('occurred_on'),
        note: json.strOrNull('note'),
        transactionId: json.strOrNull('transaction_id'),
        createdAt: json.dateVal('created_at'),
      );

  Json toInsertJson() => compactJson({
        'goal_id': goalId,
        ...moneyFields('amount', amount),
        'occurred_on': dateOnly(occurredOn),
        'note': note,
        'transaction_id': transactionId,
      });

  @override
  List<Object?> get props => [id, goalId, amount, occurredOn, note];
}
