import 'package:equatable/equatable.dart';

import '../../core/constants/enums.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/money.dart';
import 'category.dart';
import 'json_map.dart';

/// A budget at `users/{uid}/budgets/{id}`.
///
/// A budget with a null [categoryId] is an overall budget covering every
/// expense category for the period.
class Budget extends Equatable {
  const Budget({
    required this.id,
    required this.userId,
    required this.amount,
    required this.period,
    required this.startDate,
    this.endDate,
    this.categoryId,
    this.name,
    this.alertThreshold = 80,
    this.rollover = false,
    this.isArchived = false,
    this.category,
    this.spent,
    this.spentPeriodStart,
    this.alertedPeriodStart,
    this.alertedLevels = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;

  /// Null means "all expense categories".
  final String? categoryId;
  final String? name;
  final Money amount;
  final BudgetPeriod period;
  final DateTime startDate;

  /// Null for a repeating budget; set for a custom, one-off period.
  final DateTime? endDate;

  /// Percentage at which the first warning fires (e.g. 80).
  final int alertThreshold;

  /// Whether unspent budget carries into the next period.
  final bool rollover;
  final bool isArchived;
  final Category? category;

  /// Spending recorded against this budget for the period beginning
  /// [spentPeriodStart], maintained by the `onTransactionWritten` trigger.
  ///
  /// Derived, and the security rules forbid a client writing it. Null until the
  /// first transaction lands. Read it through `BudgetProgress` rather than
  /// directly: the stored figure belongs to one period, and outside that period
  /// it means nothing.
  final Money? spent;
  final DateTime? spentPeriodStart;

  /// Which period the thresholds in [alertedLevels] were raised for.
  ///
  /// Kept on the budget rather than inferred from the notifications that exist,
  /// so deleting a "75% spent" notification does not cause the next transaction
  /// to raise it again. When this does not match the current period the fired
  /// set is treated as empty, which is what makes a new month start clean.
  final DateTime? alertedPeriodStart;

  /// [BudgetAlertLevel.wire] values already raised for [alertedPeriodStart].
  final List<String> alertedLevels;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isOverall => categoryId == null;

  String get displayName =>
      name?.trim().isNotEmpty == true
          ? name!.trim()
          : (category?.name ?? 'Overall budget');

  /// The concrete date window this budget applies to for [reference].
  ///
  /// Repeating budgets are anchored on [startDate] but evaluated against the
  /// period containing [reference], so a monthly budget created in January is
  /// still meaningful in September.
  DateRange currentRange([DateTime? reference]) {
    final now = reference ?? DateTime.now();
    switch (period) {
      case BudgetPeriod.weekly:
        return DateRange(
          AppDateUtils.startOfWeek(now),
          AppDateUtils.endOfWeek(now),
        );
      case BudgetPeriod.monthly:
        return DateRange(
          AppDateUtils.startOfMonth(now),
          AppDateUtils.endOfMonth(now),
        );
      case BudgetPeriod.yearly:
        return DateRange(
          AppDateUtils.startOfYear(now),
          AppDateUtils.endOfYear(now),
        );
      case BudgetPeriod.custom:
        return DateRange(
          AppDateUtils.startOfDay(startDate),
          AppDateUtils.endOfDay(endDate ?? AppDateUtils.endOfMonth(startDate)),
        );
    }
  }

  factory Budget.fromJson(Json json) {
    final categoryJson = json.relation('category');
    return Budget(
      id: json.str('id'),
      userId: json.str('user_id'),
      categoryId: json.strOrNull('category_id'),
      name: json.strOrNull('name'),
      amount: json.money('amount'),
      period: BudgetPeriod.fromWire(json.strOrNull('period')),
      startDate: json.dateVal('start_date'),
      endDate: json.dateOrNull('end_date'),
      alertThreshold: json.intVal('alert_threshold', fallback: 80),
      rollover: json.boolVal('rollover'),
      isArchived: json.boolVal('is_archived'),
      category: categoryJson == null ? null : Category.fromJson(categoryJson),
      spent: json.moneyOrNull('spent'),
      spentPeriodStart: json.dateOrNull('spent_period_start'),
      alertedPeriodStart: json.dateOrNull('alerted_period_start'),
      alertedLevels: json.stringList('alerted_levels'),
      createdAt: json.dateVal('created_at'),
      updatedAt: json.dateVal('updated_at'),
    );
  }

  Json toInsertJson() => compactJson({
        'category_id': categoryId,
        'name': name,
        ...moneyFields('amount', amount),
        'period': period.wire,
        'start_date': dateOnly(startDate),
        'end_date': endDate == null ? null : dateOnly(endDate!),
        'alert_threshold': alertThreshold,
        'rollover': rollover,
        'is_archived': isArchived,
      });

  Json toUpdateJson() => compactJson({
        'category_id': categoryId ?? Patch.clear,
        'name': name ?? Patch.clear,
        ...moneyFields('amount', amount, withCurrency: false),
        'period': period.wire,
        'start_date': dateOnly(startDate),
        'end_date': endDate == null ? Patch.clear : dateOnly(endDate!),
        'alert_threshold': alertThreshold,
        'rollover': rollover,
        'is_archived': isArchived,
      });

  Budget copyWith({
    Object? categoryId = _sentinel,
    Object? name = _sentinel,
    Money? amount,
    BudgetPeriod? period,
    DateTime? startDate,
    Object? endDate = _sentinel,
    int? alertThreshold,
    bool? rollover,
    bool? isArchived,
    Category? category,
  }) =>
      Budget(
        id: id,
        userId: userId,
        categoryId:
            categoryId == _sentinel ? this.categoryId : categoryId as String?,
        name: name == _sentinel ? this.name : name as String?,
        amount: amount ?? this.amount,
        period: period ?? this.period,
        startDate: startDate ?? this.startDate,
        endDate: endDate == _sentinel ? this.endDate : endDate as DateTime?,
        alertThreshold: alertThreshold ?? this.alertThreshold,
        rollover: rollover ?? this.rollover,
        isArchived: isArchived ?? this.isArchived,
        category: category ?? this.category,
        spent: spent,
        spentPeriodStart: spentPeriodStart,
        alertedPeriodStart: alertedPeriodStart,
        alertedLevels: alertedLevels,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  static const Object _sentinel = Object();

  @override
  List<Object?> get props => [
        id,
        categoryId,
        name,
        amount,
        period,
        startDate,
        endDate,
        alertThreshold,
        rollover,
        isArchived,
      ];
}

/// A budget paired with the spending actually recorded against it.
///
/// This is a view model, not a stored document: [spent] comes from the figure
/// the `onTransactionWritten` trigger maintains, and is reported as zero when
/// that figure belongs to a period that has since rolled over.
class BudgetProgress extends Equatable {
  const BudgetProgress({
    required this.budget,
    required this.spent,
    required this.range,
  });

  final Budget budget;
  final Money spent;
  final DateRange range;

  Money get limit => budget.amount;

  /// Never negative: once a budget is exceeded, "remaining" is zero and the
  /// overspend is reported separately by [overspend].
  Money get remaining {
    final diff = limit - spent;
    return diff.isNegative ? Money.zero(limit.currency) : diff;
  }

  Money get overspend {
    final diff = spent - limit;
    return diff.isPositive ? diff : Money.zero(limit.currency);
  }

  /// 0–100+ (can exceed 100 when overspent).
  double get percentUsed => spent.percentOf(limit);

  /// Clamped for progress bars.
  double get progressFraction => (percentUsed / 100).clamp(0.0, 1.0);

  bool get isExceeded => spent > limit;
  bool get isAtThreshold => percentUsed >= budget.alertThreshold;

  /// Days left in the period, inclusive of today.
  int get daysRemaining {
    final today = AppDateUtils.startOfDay(DateTime.now());
    if (today.isAfter(range.end)) return 0;
    return range.end.difference(today).inDays + 1;
  }

  /// What the user can still spend per day without exceeding the budget.
  Money get dailyAllowance {
    final days = daysRemaining;
    if (days <= 0) return Money.zero(limit.currency);
    return remaining * (1 / days);
  }

  BudgetHealth get health {
    if (isExceeded) return BudgetHealth.exceeded;
    if (percentUsed >= 90) return BudgetHealth.critical;
    if (isAtThreshold) return BudgetHealth.warning;
    return BudgetHealth.healthy;
  }

  /// Every threshold this period's spending has reached, lowest first.
  List<BudgetAlertLevel> get reachedLevels => BudgetAlertLevel.values
      .where((level) => level.reachedBy(percentUsed))
      .toList(growable: false);

  /// Whether the budget's recorded alert state belongs to the period now in
  /// view. When it does not, the period has rolled over and nothing has been
  /// raised yet for the new one.
  bool get hasAlertStateForPeriod {
    final stamped = budget.alertedPeriodStart;
    return stamped != null && AppDateUtils.isSameDay(stamped, range.start);
  }

  /// Thresholds reached that have not been announced for this period.
  ///
  /// A single transaction can push a budget past several at once — from 70% to
  /// 105% — and all of them are returned, so the user gets both the "you are
  /// close" and the "you are over" rather than only whichever the code
  /// happened to check first.
  List<BudgetAlertLevel> get pendingAlerts {
    final fired = hasAlertStateForPeriod
        ? budget.alertedLevels.toSet()
        : const <String>{};
    return reachedLevels
        .where((level) => !fired.contains(level.wire))
        .toList(growable: false);
  }

  @override
  List<Object?> get props => [budget, spent, range];
}

enum BudgetHealth { healthy, warning, critical, exceeded }
