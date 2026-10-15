import 'package:equatable/equatable.dart';

import '../../core/constants/enums.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/money.dart';
import 'account.dart';
import 'category.dart';
import 'json_map.dart';

/// A row of `public.subscriptions`.
///
/// A subscription is a recurring charge the user wants to see the running cost
/// of. It is deliberately separate from `recurring_transactions`: this table
/// answers "what am I paying for every month", not "what should be posted".
class Subscription extends Equatable {
  const Subscription({
    required this.id,
    required this.userId,
    required this.name,
    required this.amount,
    required this.frequency,
    required this.nextRenewalDate,
    this.categoryId,
    this.accountId,
    this.startDate,
    this.customIntervalDays,
    this.paymentMethod,
    this.notes,
    this.reminderDays = 2,
    this.isActive = true,
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
  final RecurrenceFrequency frequency;
  final DateTime nextRenewalDate;
  final String? categoryId;
  final String? accountId;
  final DateTime? startDate;

  /// Only meaningful when [frequency] is custom.
  final int? customIntervalDays;
  final PaymentMethod? paymentMethod;
  final String? notes;
  final int reminderDays;
  final bool isActive;
  final bool isArchived;
  final Category? category;
  final Account? account;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Cost normalised to one month, so subscriptions billed yearly and monthly
  /// can be added together on the summary card.
  Money get monthlyCost => amount *
      AppDateUtils.occurrencesPerMonth(
        frequency,
        customDays: customIntervalDays ?? 30,
      );

  Money get yearlyCost => monthlyCost * 12;

  int get daysUntilRenewal {
    final today = AppDateUtils.startOfDay(DateTime.now());
    return AppDateUtils.startOfDay(nextRenewalDate).difference(today).inDays;
  }

  bool get renewsSoon => isActive && daysUntilRenewal >= 0 &&
      daysUntilRenewal <= reminderDays;

  /// Next renewal date, rolled forward if it has slipped into the past.
  DateTime get resolvedNextRenewal => AppDateUtils.nextOccurrenceAfter(
        nextRenewalDate,
        frequency,
        customDays: customIntervalDays ?? 30,
      );

  factory Subscription.fromJson(Json json) {
    final categoryJson = json.relation('category');
    final accountJson = json.relation('account');
    return Subscription(
      id: json.str('id'),
      userId: json.str('user_id'),
      name: json.str('name'),
      amount: json.money('amount'),
      frequency: RecurrenceFrequency.fromWire(json.strOrNull('frequency')),
      nextRenewalDate: json.dateVal('next_renewal_date'),
      categoryId: json.strOrNull('category_id'),
      accountId: json.strOrNull('account_id'),
      startDate: json.dateOrNull('start_date'),
      customIntervalDays: json.intOrNull('custom_interval_days'),
      paymentMethod: PaymentMethod.fromWire(json.strOrNull('payment_method')),
      notes: json.strOrNull('notes'),
      reminderDays: json.intVal('reminder_days', fallback: 2),
      isActive: json.boolVal('is_active', fallback: true),
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
        'frequency': frequency.wire,
        'next_renewal_date': dateOnly(nextRenewalDate),
        'category_id': categoryId,
        'account_id': accountId,
        'start_date': startDate == null ? null : dateOnly(startDate!),
        'custom_interval_days': customIntervalDays,
        'payment_method': paymentMethod?.wire,
        'notes': notes,
        'reminder_days': reminderDays,
        'is_active': isActive,
      });

  Json toUpdateJson() => compactJson({
        'name': name,
        ...moneyFields('amount', amount, withCurrency: false),
        'frequency': frequency.wire,
        'next_renewal_date': dateOnly(nextRenewalDate),
        'category_id': categoryId ?? Patch.clear,
        'account_id': accountId ?? Patch.clear,
        'start_date':
            startDate == null ? Patch.clear : dateOnly(startDate!),
        'custom_interval_days': customIntervalDays ?? Patch.clear,
        'payment_method': paymentMethod?.wire ?? Patch.clear,
        'notes': notes ?? Patch.clear,
        'reminder_days': reminderDays,
        'is_active': isActive,
        'is_archived': isArchived,
      });

  Subscription copyWith({
    String? name,
    Money? amount,
    RecurrenceFrequency? frequency,
    DateTime? nextRenewalDate,
    Object? categoryId = _sentinel,
    Object? accountId = _sentinel,
    Object? startDate = _sentinel,
    Object? customIntervalDays = _sentinel,
    Object? paymentMethod = _sentinel,
    Object? notes = _sentinel,
    int? reminderDays,
    bool? isActive,
    bool? isArchived,
  }) =>
      Subscription(
        id: id,
        userId: userId,
        name: name ?? this.name,
        amount: amount ?? this.amount,
        frequency: frequency ?? this.frequency,
        nextRenewalDate: nextRenewalDate ?? this.nextRenewalDate,
        categoryId:
            categoryId == _sentinel ? this.categoryId : categoryId as String?,
        accountId:
            accountId == _sentinel ? this.accountId : accountId as String?,
        startDate:
            startDate == _sentinel ? this.startDate : startDate as DateTime?,
        customIntervalDays: customIntervalDays == _sentinel
            ? this.customIntervalDays
            : customIntervalDays as int?,
        paymentMethod: paymentMethod == _sentinel
            ? this.paymentMethod
            : paymentMethod as PaymentMethod?,
        notes: notes == _sentinel ? this.notes : notes as String?,
        reminderDays: reminderDays ?? this.reminderDays,
        isActive: isActive ?? this.isActive,
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
        frequency,
        nextRenewalDate,
        categoryId,
        accountId,
        startDate,
        customIntervalDays,
        paymentMethod,
        notes,
        reminderDays,
        isActive,
        isArchived,
      ];
}

/// A row of `public.recurring_transactions` — a schedule that posts real
/// transactions. Execution is driven by a scheduled Edge Function so it works
/// even when the app is closed.
class RecurringTransaction extends Equatable {
  const RecurringTransaction({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    required this.amount,
    required this.accountId,
    required this.frequency,
    required this.startDate,
    required this.nextExecutionDate,
    this.categoryId,
    this.endDate,
    this.customIntervalDays,
    this.merchant,
    this.description,
    this.paymentMethod,
    this.notes,
    this.transferToAccountId,
    this.autoPost = true,
    this.isActive = true,
    this.lastExecutedOn,
    this.occurrenceCount = 0,
    this.category,
    this.account,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String name;
  final TransactionType type;
  final Money amount;
  final String accountId;
  final String? categoryId;
  final RecurrenceFrequency frequency;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime nextExecutionDate;
  final int? customIntervalDays;
  final String? merchant;
  final String? description;
  final PaymentMethod? paymentMethod;
  final String? notes;

  /// Destination account when [type] is a transfer.
  final String? transferToAccountId;

  /// When false, the schedule creates a PENDING transaction the user confirms
  /// rather than posting silently.
  final bool autoPost;
  final bool isActive;
  final DateTime? lastExecutedOn;
  final int occurrenceCount;
  final Category? category;
  final Account? account;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasEnded =>
      endDate != null && DateTime.now().isAfter(endDate!);

  int get daysUntilNext {
    final today = AppDateUtils.startOfDay(DateTime.now());
    return AppDateUtils.startOfDay(nextExecutionDate).difference(today).inDays;
  }

  bool get isDue => isActive && !hasEnded && daysUntilNext <= 0;

  Money get monthlyEquivalent => amount *
      AppDateUtils.occurrencesPerMonth(
        frequency,
        customDays: customIntervalDays ?? 30,
      );

  factory RecurringTransaction.fromJson(Json json) {
    final categoryJson = json.relation('category');
    final accountJson = json.relation('account');
    return RecurringTransaction(
      id: json.str('id'),
      userId: json.str('user_id'),
      name: json.str('name'),
      type: TransactionType.fromWire(json.strOrNull('type')),
      amount: json.money('amount'),
      accountId: json.str('account_id'),
      categoryId: json.strOrNull('category_id'),
      frequency: RecurrenceFrequency.fromWire(json.strOrNull('frequency')),
      startDate: json.dateVal('start_date'),
      endDate: json.dateOrNull('end_date'),
      nextExecutionDate: json.dateVal('next_execution_date'),
      customIntervalDays: json.intOrNull('custom_interval_days'),
      merchant: json.strOrNull('merchant'),
      description: json.strOrNull('description'),
      paymentMethod: PaymentMethod.fromWire(json.strOrNull('payment_method')),
      notes: json.strOrNull('notes'),
      transferToAccountId: json.strOrNull('transfer_to_account_id'),
      autoPost: json.boolVal('auto_post', fallback: true),
      isActive: json.boolVal('is_active', fallback: true),
      lastExecutedOn: json.dateOrNull('last_executed_on'),
      occurrenceCount: json.intVal('occurrence_count'),
      category: categoryJson == null ? null : Category.fromJson(categoryJson),
      account: accountJson == null ? null : Account.fromJson(accountJson),
      createdAt: json.dateVal('created_at'),
      updatedAt: json.dateVal('updated_at'),
    );
  }

  Json toInsertJson() => compactJson({
        'name': name,
        'type': type.wire,
        ...moneyFields('amount', amount),
        'account_id': accountId,
        'category_id': categoryId,
        'frequency': frequency.wire,
        'start_date': dateOnly(startDate),
        'end_date': endDate == null ? null : dateOnly(endDate!),
        'next_execution_date': dateOnly(nextExecutionDate),
        'custom_interval_days': customIntervalDays,
        'merchant': merchant,
        'description': description,
        'payment_method': paymentMethod?.wire,
        'notes': notes,
        'transfer_to_account_id': transferToAccountId,
        'auto_post': autoPost,
        'is_active': isActive,
      });

  Json toUpdateJson() => compactJson({
        'name': name,
        'type': type.wire,
        ...moneyFields('amount', amount, withCurrency: false),
        'account_id': accountId,
        'category_id': categoryId ?? Patch.clear,
        'frequency': frequency.wire,
        'start_date': dateOnly(startDate),
        'end_date': endDate == null ? Patch.clear : dateOnly(endDate!),
        'next_execution_date': dateOnly(nextExecutionDate),
        'custom_interval_days': customIntervalDays ?? Patch.clear,
        'merchant': merchant ?? Patch.clear,
        'description': description ?? Patch.clear,
        'payment_method': paymentMethod?.wire ?? Patch.clear,
        'notes': notes ?? Patch.clear,
        'transfer_to_account_id': transferToAccountId ?? Patch.clear,
        'auto_post': autoPost,
        'is_active': isActive,
      });

  RecurringTransaction copyWith({
    String? name,
    TransactionType? type,
    Money? amount,
    String? accountId,
    Object? categoryId = _sentinel,
    RecurrenceFrequency? frequency,
    DateTime? startDate,
    Object? endDate = _sentinel,
    DateTime? nextExecutionDate,
    Object? customIntervalDays = _sentinel,
    Object? merchant = _sentinel,
    Object? description = _sentinel,
    Object? paymentMethod = _sentinel,
    Object? notes = _sentinel,
    Object? transferToAccountId = _sentinel,
    bool? autoPost,
    bool? isActive,
  }) =>
      RecurringTransaction(
        id: id,
        userId: userId,
        name: name ?? this.name,
        type: type ?? this.type,
        amount: amount ?? this.amount,
        accountId: accountId ?? this.accountId,
        categoryId:
            categoryId == _sentinel ? this.categoryId : categoryId as String?,
        frequency: frequency ?? this.frequency,
        startDate: startDate ?? this.startDate,
        endDate: endDate == _sentinel ? this.endDate : endDate as DateTime?,
        nextExecutionDate: nextExecutionDate ?? this.nextExecutionDate,
        customIntervalDays: customIntervalDays == _sentinel
            ? this.customIntervalDays
            : customIntervalDays as int?,
        merchant: merchant == _sentinel ? this.merchant : merchant as String?,
        description: description == _sentinel
            ? this.description
            : description as String?,
        paymentMethod: paymentMethod == _sentinel
            ? this.paymentMethod
            : paymentMethod as PaymentMethod?,
        notes: notes == _sentinel ? this.notes : notes as String?,
        transferToAccountId: transferToAccountId == _sentinel
            ? this.transferToAccountId
            : transferToAccountId as String?,
        autoPost: autoPost ?? this.autoPost,
        isActive: isActive ?? this.isActive,
        lastExecutedOn: lastExecutedOn,
        occurrenceCount: occurrenceCount,
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
        type,
        amount,
        accountId,
        categoryId,
        frequency,
        startDate,
        endDate,
        nextExecutionDate,
        customIntervalDays,
        merchant,
        description,
        paymentMethod,
        transferToAccountId,
        autoPost,
        isActive,
      ];
}
