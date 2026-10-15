import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../shared/models/app_notification.dart';
import '../../../shared/providers/notification_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';

/// The notification centre.
///
/// Read-only by design: budget alerts come from database triggers and bill
/// reminders from a scheduled function, so what appears here is the system's
/// judgement rather than something a client could fabricate.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsControllerProvider);
    final unread = ref.watch(unreadNotificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unread.isNotEmpty)
            TextButton(
              onPressed: () => ref
                  .read(notificationsControllerProvider.notifier)
                  .markAllRead(),
              child: const Text('Mark all read'),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) async {
              if (value == 'clear') {
                final confirmed = await AppFeedback.confirm(
                  context,
                  title: 'Clear read notifications?',
                  message: 'Unread ones are kept.',
                  confirmLabel: 'Clear',
                );
                if (!confirmed || !context.mounted) return;
                await ref
                    .read(notificationsControllerProvider.notifier)
                    .clearRead();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.cleaning_services_outlined),
                  title: Text('Clear read'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(notificationsControllerProvider.notifier).refresh(),
        child: notifications.view(
          (data) => data.isEmpty
              ? const EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'Nothing to catch up on',
                  message: 'Budget warnings, bill reminders and finished '
                      'imports will appear here.',
                )
              : _NotificationsList(notifications: data),
          loading: const _NotificationsSkeleton(),
          onRetry: () =>
              ref.read(notificationsControllerProvider.notifier).refresh(),
        ),
      ),
    );
  }
}

class _NotificationsList extends ConsumerWidget {
  const _NotificationsList({required this.notifications});

  final List<AppNotification> notifications;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = notifications.where((n) => !n.isRead).toList();
    final read = notifications.where((n) => n.isRead).toList();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        if (unread.isNotEmpty) ...[
          Text(
            'NEW',
            style: context.text.labelSmall
                ?.copyWith(color: context.colors.primary),
          ),
          AppSpacing.gapMd,
          for (final notification in unread)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _NotificationCard(notification: notification),
            ),
          AppSpacing.gapLg,
        ],
        if (read.isNotEmpty) ...[
          Text(
            'EARLIER',
            style: context.text.labelSmall
                ?.copyWith(color: context.palette.textSecondary),
          ),
          AppSpacing.gapMd,
          for (final notification in read)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _NotificationCard(notification: notification),
            ),
        ],
        AppSpacing.gapXl,
      ],
    );
  }
}

class _NotificationCard extends ConsumerWidget {
  const _NotificationCard({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = switch (notification.severity) {
      NotificationSeverity.danger => context.palette.danger,
      NotificationSeverity.warning => context.palette.warning,
      NotificationSeverity.success => context.palette.income,
      NotificationSeverity.info => context.palette.info,
    };

    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        decoration: BoxDecoration(
          color: context.palette.danger
              .withValues(alpha: context.isDark ? 0.22 : 0.12),
          borderRadius: AppRadius.lgAll,
        ),
        child: Icon(
          Icons.delete_outline_rounded,
          color: context.palette.danger,
        ),
      ),
      onDismissed: (_) => ref
          .read(notificationsControllerProvider.notifier)
          .delete(notification.id),
      child: AppCard(
        // Unread rows get a tinted border rather than a bold background: the
        // list stays calm while still showing what is new.
        borderColor: notification.isRead
            ? null
            : context.colors.primary.withValues(alpha: 0.35),
        onTap: () => _open(context, ref),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(icon: notification.icon, color: color, size: 38),
            AppSpacing.hGapLg,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: context.text.titleSmall,
                        ),
                      ),
                      if (!notification.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: context.colors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  AppSpacing.gapXs,
                  Text(notification.body, style: context.text.bodySmall),
                  AppSpacing.gapSm,
                  Text(
                    DateDisplay.timeAgo(notification.createdAt),
                    style: context.text.labelSmall
                        ?.copyWith(letterSpacing: 0),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    if (!notification.isRead) {
      await ref
          .read(notificationsControllerProvider.notifier)
          .markRead(notification.id);
    }

    final link = notification.deepLink;
    if (link != null && context.mounted) context.push(link);
  }
}

class _NotificationsSkeleton extends StatelessWidget {
  const _NotificationsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: const [
        CardSkeleton(height: 100),
        SizedBox(height: AppSpacing.sm),
        CardSkeleton(height: 100),
        SizedBox(height: AppSpacing.sm),
        CardSkeleton(height: 100),
      ],
    );
  }
}
