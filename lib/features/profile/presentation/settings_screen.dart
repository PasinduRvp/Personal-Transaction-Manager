import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/currencies.dart';
import '../../../core/constants/enums.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/models/profile.dart';
import '../../../shared/providers/account_providers.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/image_source_picker.dart';
import '../../../shared/widgets/pickers.dart';
import '../../../shared/widgets/state_views.dart';

/// Settings.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: profile.view(
        (data) => _SettingsBody(profile: data),
        onRetry: () => ref.read(profileControllerProvider.notifier).refresh(),
      ),
    );
  }
}

class _SettingsBody extends ConsumerWidget {
  const _SettingsBody({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider).valueOrNull;
    final defaultAccount = ref.watch(defaultAccountProvider);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        _SettingsGroup(
          title: 'Account',
          children: [
            _SettingsRow(
              icon: Icons.person_outline_rounded,
              title: 'Profile',
              subtitle: profile.fullName ?? profile.email,
              onTap: () => context.push(AppRoutes.settingsProfile),
            ),
            _SettingsRow(
              icon: Icons.lock_outline_rounded,
              title: 'Security',
              subtitle: 'Password and session',
              onTap: () => context.push(AppRoutes.settingsSecurity),
            ),
          ],
        ),

        _SettingsGroup(
          title: 'Preferences',
          children: [
            _SettingsRow(
              icon: Icons.attach_money_rounded,
              title: 'Default currency',
              subtitle: '${profile.defaultCurrency} · '
                  '${Currencies.byCode(profile.defaultCurrency).name}',
              onTap: () => _changeCurrency(context, ref),
            ),
            _SettingsRow(
              icon: Icons.palette_outlined,
              title: 'Theme',
              subtitle: profile.themeMode.label,
              onTap: () => _changeTheme(context, ref),
            ),
            _SettingsRow(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Default account',
              subtitle: defaultAccount?.name ?? 'Not set',
              onTap: () => _changeDefaultAccount(context, ref),
            ),
            if (settings != null)
              SwitchListTile(
                value: settings.hideAmountsOnDashboard,
                onChanged: (value) => ref
                    .read(settingsControllerProvider.notifier)
                    .setHideAmounts(value),
                secondary: Icon(
                  Icons.visibility_off_outlined,
                  size: 22,
                  color: context.palette.textSecondary,
                ),
                title: Text('Hide amounts', style: context.text.titleSmall),
                subtitle: Text(
                  'Blur balances until you tap to reveal them',
                  style: context.text.bodySmall,
                ),
              ),
          ],
        ),

        _SettingsGroup(
          title: 'Notifications',
          children: [
            _SettingsRow(
              icon: Icons.notifications_none_rounded,
              title: 'Notification preferences',
              subtitle: 'Budgets, bills, subscriptions and imports',
              onTap: () => context.push(AppRoutes.settingsNotifications),
            ),
          ],
        ),

        _SettingsGroup(
          title: 'Your data',
          children: [
            _SettingsRow(
              icon: Icons.download_outlined,
              title: 'Export and delete data',
              subtitle: 'Download everything, or close your account',
              onTap: () => context.push(AppRoutes.settingsData),
            ),
            _SettingsRow(
              icon: Icons.folder_outlined,
              title: 'Documents',
              subtitle: 'Receipts and statements you uploaded',
              onTap: () => context.push(AppRoutes.documents),
            ),
          ],
        ),

        _SettingsGroup(
          title: 'About',
          children: [
            _SettingsRow(
              icon: Icons.info_outline_rounded,
              title: 'About Finora',
              onTap: () => context.push(AppRoutes.settingsAbout),
            ),
            _SettingsRow(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy',
              onTap: () => context.push(AppRoutes.settingsPrivacy),
            ),
          ],
        ),
        AppSpacing.gapXl,
      ],
    );
  }

  Future<void> _changeCurrency(BuildContext context, WidgetRef ref) async {
    final picked = await CurrencyPicker.show(
      context,
      selectedCode: profile.defaultCurrency,
    );
    if (picked == null || picked.code == profile.defaultCurrency) return;
    if (!context.mounted) return;

    // Existing accounts keep their own currency, so changing this only affects
    // what new things default to. Saying so avoids the impression that balances
    // are about to be converted.
    final confirmed = await AppFeedback.confirm(
      context,
      title: 'Change default currency?',
      message: 'New accounts and budgets will use ${picked.code}.',
      confirmLabel: 'Change',
      consequences: const [
        'Existing accounts keep their own currency.',
        'No amounts are converted.',
      ],
    );
    if (!confirmed || !context.mounted) return;

    await AppFeedback.runWithProgress(
      context,
      successMessage: 'Default currency updated',
      action: () => ref
          .read(profileControllerProvider.notifier)
          .updateDetails(defaultCurrency: picked.code),
    );
  }

  Future<void> _changeTheme(BuildContext context, WidgetRef ref) async {
    final picked = await AppFeedback.showSheet<AppThemeMode>(
      context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.sm,
              ),
              child: Text('Theme', style: context.text.titleLarge),
            ),
            const Divider(height: 1),
            for (final mode in AppThemeMode.values)
              ListTile(
                leading: Icon(switch (mode) {
                  AppThemeMode.system => Icons.brightness_auto_outlined,
                  AppThemeMode.light => Icons.light_mode_outlined,
                  AppThemeMode.dark => Icons.dark_mode_outlined,
                }),
                title: Text(mode.label, style: context.text.titleSmall),
                subtitle: mode == AppThemeMode.system
                    ? Text(
                        'Follows your device setting',
                        style: context.text.bodySmall,
                      )
                    : null,
                trailing: mode == profile.themeMode
                    ? Icon(Icons.check_rounded, color: context.colors.primary)
                    : null,
                onTap: () => Navigator.of(context).pop(mode),
              ),
          ],
        ),
      ),
    );

    if (picked != null) {
      await ref.read(profileControllerProvider.notifier).setThemeMode(picked);
    }
  }

  Future<void> _changeDefaultAccount(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final accounts = ref.read(activeAccountsProvider);
    if (accounts.isEmpty) {
      AppFeedback.showInfo(context, 'Add an account first.');
      return;
    }

    final picked = await AccountPicker.show(
      context,
      accounts: accounts,
      selectedId: ref.read(defaultAccountProvider)?.id,
      title: 'Default account',
    );
    if (picked == null || !context.mounted) return;

    await ref
        .read(settingsControllerProvider.notifier)
        .setDefaultAccount(picked.id);
    if (context.mounted) {
      AppFeedback.showSuccess(context, 'Default account set to ${picked.name}');
    }
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xs,
              bottom: AppSpacing.md,
            ),
            child: Text(
              title.toUpperCase(),
              style: context.text.labelSmall
                  ?.copyWith(color: context.palette.textSecondary),
            ),
          ),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: AppSpacing.lg),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, size: 22, color: context.palette.textSecondary),
      title: Text(title, style: context.text.titleSmall),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: context.text.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: context.palette.textTertiary,
      ),
    );
  }
}

/// Edit name, avatar and language.
class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _isLoaded = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: profile.view(
        (data) {
          if (!_isLoaded) {
            _isLoaded = true;
            _nameController.text = data.fullName ?? '';
          }
          return _buildForm(context, data);
        },
        onRetry: () => ref.read(profileControllerProvider.notifier).refresh(),
      ),
    );
  }

  Widget _buildForm(BuildContext context, Profile profile) {
    return SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.page),
          children: [
            Center(
              child: Column(
                children: [
                  _EditableAvatar(profile: profile),
                  AppSpacing.gapMd,
                  Text(profile.email, style: context.text.bodySmall),
                ],
              ),
            ),
            AppSpacing.gapXl,

            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            AppSpacing.gapLg,

            PickerField(
              label: 'Email',
              value: profile.email,
              // Changing an email address means re-verifying it, which is a
              // Supabase Auth flow rather than a profile edit.
              enabled: false,
              trailing: Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: context.palette.textTertiary,
              ),
              onTap: () {},
            ),
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.xs,
                left: AppSpacing.md,
              ),
              child: Text(
                'Contact support to change the email address on your account.',
                style: context.text.bodySmall,
              ),
            ),
            AppSpacing.gapXxl,

            FilledButton(
              onPressed: _isSubmitting ? null : _save,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.hideKeyboard();

    setState(() => _isSubmitting = true);
    try {
      await ref.read(profileControllerProvider.notifier).updateDetails(
            fullName: _nameController.text.trim(),
          );
      if (!mounted) return;
      AppFeedback.showSuccess(context, 'Profile updated');
      context.pop();
    } on Object catch (error) {
      if (mounted) AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

class _EditableAvatar extends ConsumerWidget {
  const _EditableAvatar({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(avatarBytesProvider).valueOrNull;

    return Stack(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: context.colors.primaryContainer,
            shape: BoxShape.circle,
            image: bytes == null
                ? null
                : DecorationImage(
                    // The bucket is private, so the image comes from memory
                    // rather than from a URL a network image could fetch.
                    image: MemoryImage(bytes),
                    fit: BoxFit.cover,
                  ),
          ),
          alignment: Alignment.center,
          child: bytes != null
              ? null
              : Text(
                  profile.initials,
                  style: context.text.headlineMedium
                      ?.copyWith(color: context.colors.onPrimaryContainer),
                ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Material(
            color: context.colors.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _showAvatarOptions(context, ref),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Icon(
                  Icons.photo_camera_outlined,
                  size: 16,
                  color: context.colors.onPrimary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showAvatarOptions(BuildContext context, WidgetRef ref) async {
    final action = await AppFeedback.showSheet<String>(
      context,
      isScrollControlled: false,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose a photo'),
              onTap: () => Navigator.of(context).pop('pick'),
            ),
            if (profile.profileImageUrl != null)
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: context.palette.danger,
                ),
                title: Text(
                  'Remove photo',
                  style: TextStyle(color: context.palette.danger),
                ),
                onTap: () => Navigator.of(context).pop('remove'),
              ),
          ],
        ),
      ),
    );

    if (action == null || !context.mounted) return;

    if (action == 'remove') {
      await AppFeedback.runWithProgress(
        context,
        successMessage: 'Photo removed',
        action: () =>
            ref.read(profileControllerProvider.notifier).removeAvatar(),
      );
      return;
    }

    await AvatarPicker.pickAndUpload(context, ref);
  }
}

/// Picks and uploads a profile photo.
///
/// Compressed before upload: an avatar is displayed at 96 logical pixels, so a
/// multi-megabyte original is pure waste of the user's bandwidth and storage.
class AvatarPicker {
  const AvatarPicker._();

  static Future<void> pickAndUpload(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      final result = await ImageSourcePicker.pick(context);
      if (result == null || !context.mounted) return;

      await AppFeedback.runWithProgress(
        context,
        progressMessage: 'Uploading photo…',
        successMessage: 'Photo updated',
        action: () => ref.read(profileControllerProvider.notifier).uploadAvatar(
              bytes: result.bytes,
              fileName: result.fileName,
            ),
      );
    } on Object catch (error) {
      if (context.mounted) AppFeedback.showError(context, error);
    }
  }
}
