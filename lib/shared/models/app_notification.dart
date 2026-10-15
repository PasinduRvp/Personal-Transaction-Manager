import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../core/constants/enums.dart';
import 'json_map.dart';

/// A row of `public.notifications` — the in-app notification centre.
///
/// Rows are written by the database (budget triggers) and by scheduled Edge
/// Functions (bills, subscriptions, recurring). The client only reads them and
/// marks them read, so a notification cannot be forged by a client.
class AppNotification extends Equatable {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.isRead = false,
    this.readAt,
    this.entityType,
    this.entityId,
    this.payload = const {},
  });

  final String id;
  final String userId;
  final NotificationKind kind;
  final String title;
  final String body;
  final bool isRead;
  final DateTime? readAt;

  /// What the notification refers to, e.g. `budget`, `bill`, `ocr_job`.
  final String? entityType;
  final String? entityId;
  final Json payload;
  final DateTime createdAt;

  IconData get icon => switch (kind) {
        NotificationKind.budgetWarning => Icons.warning_amber_rounded,
        NotificationKind.budgetExceeded => Icons.error_outline_rounded,
        NotificationKind.billDue => Icons.event_outlined,
        NotificationKind.subscriptionRenewal => Icons.autorenew_rounded,
        NotificationKind.recurringDue => Icons.repeat_rounded,
        NotificationKind.ocrCompleted => Icons.document_scanner_outlined,
        NotificationKind.ocrFailed => Icons.report_gmailerrorred_outlined,
        NotificationKind.goalReached => Icons.emoji_events_outlined,
        NotificationKind.creditCardDue => Icons.credit_score_outlined,
      };

  /// Severity drives the icon colour on the notification row.
  NotificationSeverity get severity => switch (kind) {
        NotificationKind.budgetExceeded => NotificationSeverity.danger,
        NotificationKind.ocrFailed => NotificationSeverity.danger,
        NotificationKind.budgetWarning => NotificationSeverity.warning,
        NotificationKind.billDue => NotificationSeverity.warning,
        NotificationKind.subscriptionRenewal => NotificationSeverity.info,
        NotificationKind.recurringDue => NotificationSeverity.info,
        NotificationKind.ocrCompleted => NotificationSeverity.success,
        NotificationKind.goalReached => NotificationSeverity.success,
        NotificationKind.creditCardDue => NotificationSeverity.warning,
      };

  /// In-app route this notification should open, or null when it is purely
  /// informational.
  String? get deepLink {
    final id = entityId;
    if (id == null) return null;
    return switch (entityType) {
      'budget' => '/budgets/$id',
      'bill' => '/bills',
      'subscription' => '/subscriptions',
      'savings_goal' => '/savings/$id',
      'transaction' => '/transactions/$id',
      'ocr_job' => '/documents/$id',
      'account' => '/accounts/$id',
      _ => null,
    };
  }

  factory AppNotification.fromJson(Json json) => AppNotification(
        id: json.str('id'),
        userId: json.str('user_id'),
        kind: NotificationKind.fromWire(json.strOrNull('kind')),
        title: json.str('title'),
        body: json.str('body'),
        isRead: json.boolVal('is_read'),
        readAt: json.dateOrNull('read_at'),
        entityType: json.strOrNull('entity_type'),
        entityId: json.strOrNull('entity_id'),
        payload: json.jsonVal('payload'),
        createdAt: json.dateVal('created_at'),
      );

  AppNotification copyWith({bool? isRead, DateTime? readAt}) =>
      AppNotification(
        id: id,
        userId: userId,
        kind: kind,
        title: title,
        body: body,
        isRead: isRead ?? this.isRead,
        readAt: readAt ?? this.readAt,
        entityType: entityType,
        entityId: entityId,
        payload: payload,
        createdAt: createdAt,
      );

  @override
  List<Object?> get props =>
      [id, kind, title, body, isRead, entityType, entityId, createdAt];
}

enum NotificationSeverity { info, success, warning, danger }
