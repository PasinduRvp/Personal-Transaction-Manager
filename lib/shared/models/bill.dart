import 'package:equatable/equatable.dart';

import '../../core/constants/enums.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/money.dart';
import 'account.dart';
import 'category.dart';
import 'json_map.dart';

/// A row of `public.bills`.
///
/// [status] is stored, but "overdue" is derived rather than trusted: a bill
/// whose due date has passed reads as overdue even if no background job has
/// run to update the column.
class Bill extends Equatable {
  const Bill({
    required this.id,
    required this.userId,
    required this.name,
    required this.amount,
    required this.dueDate,
    this.categoryId,
    this.accountId,
    this.frequency,
    this.reminderDays = 3,
    this.status = BillStatus.unpaid,
    this.notes,
    this.autoPay = false,
    this.lastPaidOn,
    this.paidTransactionId,
    this.isArchived = false,
    this.category,
    this.account,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String name;
  final Money amount;
  final DateTime dueDate;
  final String? categoryId;
  final String? accountId;

  /// Null for a one-off bill.
  final RecurrenceFrequency? frequency;

  /// How many days before the due date to notify.
  final int reminderDays;
  final BillStatus status;
  final String? notes;
  final bool autoPay;
  final DateTime? lastPaidOn;
  final String? paidTransactionId;
  final bool isArchived;
  final Category? category;
  final Account? account;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isRecurring => frequency != null;
  bool get isPaid => status == BillStatus.paid;
  bool get isCancelled => status == BillStatus.cancelled;

  /// Days until due; negative when overdue.
  int get daysUntilDue {
    final today = AppDateUtils.startOfDay(DateTime.now());
    return AppDateUtils.startOfDay(dueDate).difference(today).inDays;
  }

  /// The status to display, treating a past due date as overdue.
  BillStatus get effectiveStatus {
    if (isPaid || isCancelled) return status;
    return daysUntilDue < 0 ? BillStatus.overdue : status;
  }

  bool get isOverdue => effectiveStatus == BillStatus.overdue;
  bool get isDueToday => !isPaid && !isCancelled && daysUntilDue == 0;
  bool get isDueTomorrow => !isPaid && !isCancelled && daysUntilDue == 1;
  bool get isDueThisWeek =>
      !isPaid && !isCancelled && daysUntilDue > 1 && daysUntilDue <= 7;

  /// Which bucket this bill belongs to on the Bills screen.
  BillBucket get bucket {
    if (isCancelled) return BillBucket.cancelled;
    if (isPaid) return BillBucket.paid;
    if (isOverdue) return BillBucket.overdue;
    if (isDueToday) return BillBucket.dueToday;
    if (isDueTomorrow) return BillBucket.dueTomorrow;
    if (isDueThisWeek) return BillBucket.dueThisWeek;
    return BillBucket.upcoming;
  }

  bool get shouldRemindToday {
    if (isPaid || isCancelled) return false;
    final days = daysUntilDue;
    return days >= 0 && days <= reminderDays;
  }

  /// Due date of the next occurrence, for a recurring bill.
  DateTime? get nextDueDate {
    final f = frequency;
    if (f == null) return null;
    return AppDateUtils.advance(dueDate, f);
  }

  factory Bill.fromJson(Json json) {
    final categoryJson = json.relation('category');
    final accountJson = json.relation('account');
    return Bill(
      id: json.str('id'),
      userId: json.str('user_id'),
      name: json.str('name'),
      amount: json.money('amount'),
      dueDate: json.dateVal('due_date'),
      categoryId: json.strOrNull('category_id'),
      accountId: json.strOrNull('account_id'),
      frequency: json.strOrNull('frequency') == null
          ? null
          : RecurrenceFrequency.fromWire(json.strOrNull('frequency')),
      reminderDays: json.intVal('reminder_days', fallback: 3),
      status: BillStatus.fromWire(json.strOrNull('status')),
      notes: json.strOrNull('notes'),
      autoPay: json.boolVal('auto_pay'),
      lastPaidOn: json.dateOrNull('last_paid_on'),
      paidTransactionId: json.strOrNull('paid_transaction_id'),
      isArchived: json.boolVal('is_archived'),
      category: categoryJson == null ? null : Category.fromJson(categoryJson),
      account: accountJson == null ? null : Account.fromJson(accountJson),
      createdAt: json.dateVal('created_at'),
      updatedAt: json.dateVal('updated_at'),
    );
  }

  Json toInsertJson() => compactJson({
        'name': name,
        ...moneyFields('amount', amount),
        'due_date': dateOnly(dueDate),
        'category_id': categoryId,
        'account_id': accountId,
        'frequency': frequency?.wire,
        'reminder_days': reminderDays,
        'status': status.wire,
        'notes': notes,
        'auto_pay': autoPay,
      });

  Json toUpdateJson() => compactJson({
        'name': name,
        ...moneyFields('amount', amount, withCurrency: false),
        'due_date': dateOnly(dueDate),
        'category_id': categoryId ?? Patch.clear,
        'account_id': accountId ?? Patch.clear,
        'frequency': frequency?.wire ?? Patch.clear,
        'reminder_days': reminderDays,
        'status': status.wire,
        'notes': notes ?? Patch.clear,
        'auto_pay': autoPay,
        'last_paid_on':
            lastPaidOn == null ? Patch.clear : dateOnly(lastPaidOn!),
        'paid_transaction_id': paidTransactionId ?? Patch.clear,
        'is_archived': isArchived,
      });

  Bill copyWith({
    String? name,
    Money? amount,
    DateTime? dueDate,
    Object? categoryId = _sentinel,
    Object? accountId = _sentinel,
    Object? frequency = _sentinel,
    int? reminderDays,
    BillStatus? status,
    Object? notes = _sentinel,
    bool? autoPay,
    Object? lastPaidOn = _sentinel,
    Object? paidTransactionId = _sentinel,
    bool? isArchived,
  }) =>
      Bill(
        id: id,
        userId: userId,
        name: name ?? this.name,
        amount: amount ?? this.amount,
        dueDate: dueDate ?? this.dueDate,
        categoryId:
            categoryId == _sentinel ? this.categoryId : categoryId as String?,
        accountId:
            accountId == _sentinel ? this.accountId : accountId as String?,
        frequency: frequency == _sentinel
            ? this.frequency
            : frequency as RecurrenceFrequency?,
        reminderDays: reminderDays ?? this.reminderDays,
        status: status ?? this.status,
        notes: notes == _sentinel ? this.notes : notes as String?,
        autoPay: autoPay ?? this.autoPay,
        lastPaidOn:
            lastPaidOn == _sentinel ? this.lastPaidOn : lastPaidOn as DateTime?,
        paidTransactionId: paidTransactionId == _sentinel
            ? this.paidTransactionId
            : paidTransactionId as String?,
        isArchived: isArchived ?? this.isArchived,
        category: category,
        account: account,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  static const Object _sentinel = Object();

  @override
  List<Object?> get props => [
        id,
        name,
        amount,
        dueDate,
        categoryId,
        accountId,
        frequency,
        reminderDays,
        status,
        notes,
        autoPay,
        lastPaidOn,
        isArchived,
      ];
}

enum BillBucket {
  overdue('Overdue'),
  dueToday('Due today'),
  dueTomorrow('Due tomorrow'),
  dueThisWeek('Due this week'),
  upcoming('Upcoming'),
  paid('Paid'),
  cancelled('Cancelled');

  const BillBucket(this.label);
  final String label;
}
