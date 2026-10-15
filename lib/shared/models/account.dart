import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../core/constants/enums.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money.dart';
import 'json_map.dart';

/// A row of `public.accounts`.
///
/// `current_balance` is maintained by database triggers on `transactions`, so
/// the client never computes or writes it. That keeps the balance correct even
/// when two devices post transactions concurrently.
class Account extends Equatable {
  const Account({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    required this.currency,
    required this.initialBalance,
    required this.currentBalance,
    this.institutionName,
    this.accountNumberLast4,
    this.creditLimit,
    this.statementDay,
    this.paymentDueDay,
    this.iconName,
    this.colorHex,
    this.isActive = true,
    this.isArchived = false,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String name;
  final AccountType type;
  final String currency;
  final Money initialBalance;
  final Money currentBalance;
  final String? institutionName;

  /// Only the last four digits are ever stored. Full account and card numbers
  /// must never reach the database.
  final String? accountNumberLast4;
  final Money? creditLimit;

  /// Day of the month (1-31) a credit card's statement closes, and the day its
  /// payment is due. Null for every other account type.
  ///
  /// Stored as a plain day-of-month rather than a date: a statement date
  /// recurs every billing cycle, and clamping it against a short month (a 31
  /// against February) happens wherever it is used, not here.
  final int? statementDay;
  final int? paymentDueDay;
  final String? iconName;
  final String? colorHex;
  final bool isActive;
  final bool isArchived;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// `Commercial Bank •••• 4321`
  String get subtitle {
    final parts = <String>[
      if (institutionName != null && institutionName!.isNotEmpty)
        institutionName!
      else
        type.label,
      if (accountNumberLast4 != null) '•••• $accountNumberLast4',
    ];
    return parts.join(' · ');
  }

  Color get color =>
      AppColors.tryParseHex(colorHex) ?? AppColors.deterministic(id);

  IconData get icon => switch (type) {
        AccountType.cash => Icons.payments_outlined,
        AccountType.bank => Icons.account_balance_outlined,
        AccountType.savings => Icons.savings_outlined,
        AccountType.debitCard => Icons.credit_card_outlined,
        AccountType.creditCard => Icons.credit_score_outlined,
        AccountType.eWallet => Icons.account_balance_wallet_outlined,
        AccountType.other => Icons.wallet_outlined,
      };

  /// Remaining credit on a credit card. Null for every other account type.
  Money? get availableCredit {
    if (!type.isCredit || creditLimit == null) return null;
    // A credit card balance is held as a negative number when money is owed.
    return creditLimit! + currentBalance;
  }

  double? get creditUtilisation {
    final limit = creditLimit;
    if (!type.isCredit || limit == null || limit.isZero) return null;
    return currentBalance.abs.percentOf(limit).clamp(0, 999);
  }

  /// The next date this card's payment is due, counting forward from today.
  ///
  /// Clamped against short months the same way a recurring schedule is: a due
  /// day of 31 lands on the 28th in February rather than rolling into March.
  DateTime? get nextPaymentDueDate {
    final day = paymentDueDay;
    if (!type.isCredit || day == null) return null;

    final now = DateTime.now();
    DateTime forMonth(int year, int month) {
      final lastDayOfMonth = DateTime(year, month + 1, 0).day;
      return DateTime(year, month, day.clamp(1, lastDayOfMonth));
    }

    final thisMonth = forMonth(now.year, now.month);
    final today = DateTime(now.year, now.month, now.day);
    if (!thisMonth.isBefore(today)) return thisMonth;

    final nextMonth = now.month == 12 ? 1 : now.month + 1;
    final nextYear = now.month == 12 ? now.year + 1 : now.year;
    return forMonth(nextYear, nextMonth);
  }

  /// Days from today until [nextPaymentDueDate], or null when there is none.
  int? get daysUntilPaymentDue {
    final due = nextPaymentDueDate;
    if (due == null) return null;
    final now = DateTime.now();
    return due.difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  /// Whether the account contributes to the dashboard's total balance.
  bool get countsTowardNetBalance => isActive && !isArchived;

  factory Account.fromJson(Json json) {
    final currency = json.str('currency', fallback: 'LKR');
    return Account(
      id: json.str('id'),
      userId: json.str('user_id'),
      name: json.str('name'),
      type: AccountType.fromWire(json.strOrNull('type')),
      currency: currency,
      initialBalance: json.money('initial_balance'),
      currentBalance: json.money('current_balance'),
      institutionName: json.strOrNull('institution_name'),
      accountNumberLast4: json.strOrNull('account_number_last4'),
      creditLimit: json.moneyOrNull('credit_limit'),
      statementDay: json.intOrNull('statement_day'),
      paymentDueDay: json.intOrNull('payment_due_day'),
      iconName: json.strOrNull('icon'),
      colorHex: json.strOrNull('color'),
      isActive: json.boolVal('is_active', fallback: true),
      isArchived: json.boolVal('is_archived'),
      sortOrder: json.intVal('sort_order'),
      createdAt: json.dateVal('created_at'),
      updatedAt: json.dateVal('updated_at'),
    );
  }

  /// Insert payload. `user_id` is omitted deliberately: the database default is
  /// `auth.uid()`, so a client can never write a row for another user.
  Json toInsertJson() => compactJson({
        'name': name,
        'type': type.wire,
        'currency': currency,
        ...moneyFields('initial_balance', initialBalance, withCurrency: false),
        'institution_name': institutionName,
        'account_number_last4': accountNumberLast4,
        ...moneyFields('credit_limit', creditLimit, withCurrency: false),
        'statement_day': statementDay,
        'payment_due_day': paymentDueDay,
        'icon': iconName,
        'color': colorHex,
        'is_active': isActive,
        'is_archived': isArchived,
        'sort_order': sortOrder,
      });

  Json toUpdateJson() => compactJson({
        'name': name,
        'type': type.wire,
        'institution_name': institutionName,
        'account_number_last4': accountNumberLast4,
        ...moneyFields('credit_limit', creditLimit, withCurrency: false),
        'statement_day': statementDay,
        'payment_due_day': paymentDueDay,
        'icon': iconName,
        'color': colorHex,
        'is_active': isActive,
        'is_archived': isArchived,
        'sort_order': sortOrder,
      });

  Account copyWith({
    String? name,
    AccountType? type,
    String? currency,
    Money? initialBalance,
    Money? currentBalance,
    Object? institutionName = _sentinel,
    Object? accountNumberLast4 = _sentinel,
    Object? creditLimit = _sentinel,
    Object? statementDay = _sentinel,
    Object? paymentDueDay = _sentinel,
    Object? iconName = _sentinel,
    Object? colorHex = _sentinel,
    bool? isActive,
    bool? isArchived,
    int? sortOrder,
  }) =>
      Account(
        id: id,
        userId: userId,
        name: name ?? this.name,
        type: type ?? this.type,
        currency: currency ?? this.currency,
        initialBalance: initialBalance ?? this.initialBalance,
        currentBalance: currentBalance ?? this.currentBalance,
        institutionName: institutionName == _sentinel
            ? this.institutionName
            : institutionName as String?,
        accountNumberLast4: accountNumberLast4 == _sentinel
            ? this.accountNumberLast4
            : accountNumberLast4 as String?,
        creditLimit:
            creditLimit == _sentinel ? this.creditLimit : creditLimit as Money?,
        statementDay: statementDay == _sentinel
            ? this.statementDay
            : statementDay as int?,
        paymentDueDay: paymentDueDay == _sentinel
            ? this.paymentDueDay
            : paymentDueDay as int?,
        iconName: iconName == _sentinel ? this.iconName : iconName as String?,
        colorHex: colorHex == _sentinel ? this.colorHex : colorHex as String?,
        isActive: isActive ?? this.isActive,
        isArchived: isArchived ?? this.isArchived,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  static const Object _sentinel = Object();

  @override
  List<Object?> get props => [
        id,
        name,
        type,
        currency,
        initialBalance,
        currentBalance,
        institutionName,
        accountNumberLast4,
        creditLimit,
        statementDay,
        paymentDueDay,
        iconName,
        colorHex,
        isActive,
        isArchived,
        sortOrder,
      ];
}
