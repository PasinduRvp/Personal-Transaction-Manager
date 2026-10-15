import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/models/profile.dart';
import '../../../shared/providers/account_providers.dart';
import '../../../shared/providers/auth_providers.dart';
import '../../../shared/providers/notification_providers.dart';
import '../../../shared/providers/ocr_providers.dart';
import '../../../shared/providers/planning_providers.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';

/// The profile tab: identity, the things a user manages, and settings.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileControllerProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(profileControllerProvider.notifier).refresh(),
          child: profile.view(
            (data) => _ProfileBody(profile: data),
            loading: const _ProfileSkeleton(),
            onRetry: () =>
                ref.read(profileControllerProvider.notifier).refresh(),
          ),
        ),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(activeAccountsProvider).length;
    final budgets = ref.watch(budgetsControllerProvider).valueOrNull?.length ?? 0;
    final goals = ref.watch(savingsControllerProvider).valueOrNull?.length ?? 0;
    final pendingImports =
        ref.watch(pendingCandidateCountProvider).valueOrNull ?? 0;
    final unread = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.lg,
        AppSpacing.page,
        AppSpacing.bottomNavClearance,
      ),
      children: [
        _ProfileHeader(profile: profile),
        AppSpacing.gapXl,

        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              _MenuRow(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Accounts',
                trailing: '$accounts',
                onTap: () => context.push(AppRoutes.accounts),
              ),
              const Divider(height: 1, indent: AppSpacing.lg),
              _MenuRow(
                icon: Icons.category_outlined,
                title: 'Categories',
                onTap: () => context.push(AppRoutes.categories),
              ),
              const Divider(height: 1, indent: AppSpacing.lg),
              _MenuRow(
                icon: Icons.pie_chart_outline_rounded,
                title: 'Budgets',
                trailing: '$budgets',
                onTap: () => context.go(AppRoutes.budgets),
              ),
              const Divider(height: 1, indent: AppSpacing.lg),
              _MenuRow(
                icon: Icons.savings_outlined,
                title: 'Savings goals',
                trailing: '$goals',
                onTap: () => context.push(AppRoutes.savings),
              ),
            ],
          ),
        ),
        AppSpacing.gapLg,

        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              _MenuRow(
                icon: Icons.receipt_long_outlined,
                title: 'Bills',
                onTap: () => context.push(AppRoutes.bills),
              ),
              const Divider(height: 1, indent: AppSpacing.lg),
              _MenuRow(
                icon: Icons.subscriptions_outlined,
                title: 'Subscriptions',
                onTap: () => context.push(AppRoutes.subscriptions),
              ),
              const Divider(height: 1, indent: AppSpacing.lg),
              _MenuRow(
                icon: Icons.repeat_rounded,
                title: 'Recurring transactions',
                onTap: () => context.push(AppRoutes.recurring),
              ),
            ],
          ),
        ),
        AppSpacing.gapLg,

        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              _MenuRow(
                icon: Icons.folder_outlined,
                title: 'Documents',
                onTap: () => context.push(AppRoutes.documents),
              ),
              const Divider(height: 1, indent: AppSpacing.lg),
              _MenuRow(
                icon: Icons.document_scanner_outlined,
                title: 'Import history',
                badge: pendingImports > 0 ? '$pendingImports' : null,
                onTap: () => context.push(AppRoutes.importHistory),
              ),
              const Divider(height: 1, indent: AppSpacing.lg),
              _MenuRow(
                icon: Icons.summarize_outlined,
                title: 'Reports and export',
                onTap: () => context.push(AppRoutes.reports),
              ),
            ],
          ),
        ),
        AppSpacing.gapLg,

        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              _MenuRow(
                icon: Icons.notifications_none_rounded,
                title: 'Notifications',
                badge: unread > 0 ? '$unread' : null,
                onTap: () => context.push(AppRoutes.notifications),
              ),
              const Divider(height: 1, indent: AppSpacing.lg),
              _MenuRow(
                icon: Icons.settings_outlined,
                title: 'Settings',
                onTap: () => context.push(AppRoutes.settings),
              ),
            ],
          ),
        ),
        AppSpacing.gapXl,

        OutlinedButton.icon(
          onPressed: () => _signOut(context, ref),
          icon: Icon(
            Icons.logout_rounded,
            size: 18,
            color: context.palette.danger,
          ),
          label: Text(
            'Sign out',
            style: TextStyle(color: context.palette.danger),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(
              color: context.palette.danger.withValues(alpha: 0.4),
            ),
          ),
        ),
        AppSpacing.gapXl,
        Center(
          child: Text(
            'Finora · version 1.0.0',
            style: context.text.bodySmall,
          ),
        ),
      ],
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await AppFeedback.confirm(
      context,
      title: 'Sign out?',
      message: 'Your saved data on this device will be cleared. Everything '
          'stays in your account.',
      confirmLabel: 'Sign out',
    );
    if (!confirmed || !context.mounted) return;

    await ref.read(authControllerProvider.notifier).signOut();
    // The router redirects on the auth state change, so no navigation here.
  }
}

class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatarBytes = ref.watch(avatarBytesProvider).valueOrNull;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      onTap: () => context.push(AppRoutes.settingsProfile),
      child: Row(
        children: [
          _Avatar(profile: profile, bytes: avatarBytes),
          AppSpacing.hGapLg,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.fullName ?? profile.displayName,
                  style: context.text.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  profile.email,
                  style: context.text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                AppSpacing.gapSm,
                Row(
                  children: [
                    AppChipLabel(
                      label: profile.defaultCurrency,
                      dense: true,
                    ),
                    AppSpacing.hGapSm,
                    AppChipLabel(
                      label: profile.themeMode.label,
                      dense: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: context.palette.textTertiary,
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.profile, this.bytes, this.size = 60});

  final Profile profile;

  /// The avatar's bytes, or null while loading or when there is none.
  ///
  /// Bytes rather than a URL: the storage bucket is private and the image is read
  /// through the authenticated SDK, so there is no address to hand a network
  /// image widget.
  final Uint8List? bytes;

  final double size;

  @override
  Widget build(BuildContext context) {
    if (bytes == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: context.colors.primaryContainer,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          profile.initials,
          style: context.text.titleLarge
              ?.copyWith(color: context.colors.onPrimaryContainer),
        ),
      );
    }

    return ClipOval(
      child: Image.memory(
        bytes!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 3).round(),
        // A failed avatar falls back to initials rather than a broken-image
        // glyph.
        errorBuilder: (context, _, __) => _Avatar(profile: profile, size: size),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.trailing,
    this.badge,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? trailing;

  /// A count that needs attention, shown in the accent colour.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, size: 22, color: context.palette.textSecondary),
      title: Text(title, style: context.text.titleSmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: context.colors.primary,
                borderRadius: AppRadius.pillAll,
              ),
              child: Text(
                badge!,
                style: context.text.labelSmall?.copyWith(
                  color: context.colors.onPrimary,
                  letterSpacing: 0,
                ),
              ),
            )
          else if (trailing != null)
            Text(trailing!, style: context.text.bodyMedium),
          AppSpacing.hGapSm,
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: context.palette.textTertiary,
          ),
        ],
      ),
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: const [
        CardSkeleton(height: 110),
        SizedBox(height: AppSpacing.xl),
        CardSkeleton(height: 200),
        SizedBox(height: AppSpacing.lg),
        CardSkeleton(height: 150),
      ],
    );
  }
}
