import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../core/constants/enums.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/money.dart';
import 'json_map.dart';

/// A row of `public.lendings` — money lent to, or borrowed from, someone who
/// is not tracked as an account of their own.
///
/// [outstanding] starts equal to [principal] and is reduced by each repayment,
/// the same shape `SavingsGoal.currentAmount` uses for contributions. Every
/// movement — the principal going out (or in) and every repayment coming back
/// (or going out again) — is also written as a real `TRANSFER`-typed
/// transaction tagged with this record's id, so the account balance always
/// reflects it without the money ever being miscounted as income or expense:
/// transfers are excluded from the rollups and budgets everywhere else in the
/// app already.
class LendingRecord extends Equatable {
  const LendingRecord({
    required this.id,
    required this.userId,
    required this.personName,
    required this.kind,
    required this.principal,
    required this.outstanding,
    required this.accountId,
    this.notes,
    this.dueDate,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String personName;
  final LendingKind kind;
  final Money principal;
  final Money outstanding;

  /// The account the principal actually moved through.
  final String accountId;
  final String? notes;
  final DateTime? dueDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get currency => principal.currency;

  bool get isSettled => outstanding.isZero;

  Money get repaidAmount => principal - outstanding;

  double get progressFraction =>
      (repaidAmount.percentOf(principal) / 100).clamp(0.0, 1.0);

  bool get isOverdue {
    final due = dueDate;
    if (due == null || isSettled) return false;
    final today = AppDateUtils.startOfDay(DateTime.now());
    return AppDateUtils.startOfDay(due).isBefore(today);
  }

  Color get color => AppColors.deterministic(id);

  IconData get icon =>
      kind.isReceivable ? Icons.call_received_rounded : Icons.call_made_rounded;

  factory LendingRecord.fromJson(Json json) => LendingRecord(
        id: json.str('id'),
        userId: json.str('user_id'),
        personName: json.str('person_name'),
        kind: LendingKind.fromWire(json.strOrNull('kind')),
        principal: json.money('principal'),
        outstanding: json.money('outstanding'),
        accountId: json.str('account_id'),
        notes: json.strOrNull('notes'),
        dueDate: json.dateOrNull('due_date'),
        createdAt: json.dateVal('created_at'),
        updatedAt: json.dateVal('updated_at'),
      );

  Json toInsertJson() => compactJson({
        'person_name': personName,
        'kind': kind.wire,
        ...moneyFields('principal', principal),
        ...moneyFields('outstanding', outstanding, withCurrency: false),
        'account_id': accountId,
        'notes': notes,
        'due_date': dueDate == null ? null : dateOnly(dueDate!),
      });

  Json toUpdateJson() => compactJson({
        'person_name': personName,
        'notes': notes ?? Patch.clear,
        'due_date': dueDate == null ? Patch.clear : dateOnly(dueDate!),
      });

  LendingRecord copyWith({
    String? personName,
    Money? outstanding,
    Object? notes = _sentinel,
    Object? dueDate = _sentinel,
  }) =>
      LendingRecord(
        id: id,
        userId: userId,
        personName: personName ?? this.personName,
        kind: kind,
        principal: principal,
        outstanding: outstanding ?? this.outstanding,
        accountId: accountId,
        notes: notes == _sentinel ? this.notes : notes as String?,
        dueDate: dueDate == _sentinel ? this.dueDate : dueDate as DateTime?,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  static const Object _sentinel = Object();

  @override
  List<Object?> get props => [
        id,
        personName,
        kind,
        principal,
        outstanding,
        accountId,
        notes,
        dueDate,
      ];
}
