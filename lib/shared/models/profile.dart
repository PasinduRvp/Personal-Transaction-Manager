import 'package:equatable/equatable.dart';

import '../../core/constants/enums.dart';
import 'json_map.dart';

/// A row of `public.profiles`, created automatically by a database trigger when
/// a user signs up.
class Profile extends Equatable {
  const Profile({
    required this.id,
    required this.email,
    this.fullName,
    this.profileImageUrl,
    this.defaultCurrency = 'LKR',
    this.timezone = 'Asia/Colombo',
    this.language = 'en',
    this.themeMode = AppThemeMode.system,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Same value as `auth.users.id`.
  final String id;
  final String email;
  final String? fullName;
  final String? profileImageUrl;
  final String defaultCurrency;
  final String timezone;
  final String language;
  final AppThemeMode themeMode;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// First name, for the dashboard greeting. Falls back to the local part of
  /// the email address so the greeting is never empty.
  String get displayName {
    final name = fullName?.trim();
    if (name != null && name.isNotEmpty) return name.split(' ').first;
    final local = email.split('@').first;
    return local.isEmpty ? 'there' : local;
  }

  String get initials {
    final name = fullName?.trim();
    if (name == null || name.isEmpty) {
      return email.isEmpty ? '?' : email[0].toUpperCase();
    }
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  factory Profile.fromJson(Json json) => Profile(
        id: json.str('id'),
        email: json.str('email'),
        fullName: json.strOrNull('full_name'),
        profileImageUrl: json.strOrNull('profile_image_url'),
        defaultCurrency: json.str('default_currency', fallback: 'LKR'),
        timezone: json.str('timezone', fallback: 'Asia/Colombo'),
        language: json.str('language', fallback: 'en'),
        themeMode: AppThemeMode.fromWire(json.strOrNull('theme')),
        createdAt: json.dateVal('created_at'),
        updatedAt: json.dateVal('updated_at'),
      );

  /// Only user-editable columns. `id` and `email` are never sent: identity is
  /// owned by Supabase Auth.
  Json toUpdateJson() => compactJson({
        'full_name': fullName,
        'profile_image_url': profileImageUrl,
        'default_currency': defaultCurrency,
        'timezone': timezone,
        'language': language,
        'theme': themeMode.wire,
      });

  Profile copyWith({
    String? fullName,
    Object? profileImageUrl = _sentinel,
    String? defaultCurrency,
    String? timezone,
    String? language,
    AppThemeMode? themeMode,
  }) =>
      Profile(
        id: id,
        email: email,
        fullName: fullName ?? this.fullName,
        profileImageUrl: profileImageUrl == _sentinel
            ? this.profileImageUrl
            : profileImageUrl as String?,
        defaultCurrency: defaultCurrency ?? this.defaultCurrency,
        timezone: timezone ?? this.timezone,
        language: language ?? this.language,
        themeMode: themeMode ?? this.themeMode,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  static const Object _sentinel = Object();

  @override
  List<Object?> get props => [
        id,
        email,
        fullName,
        profileImageUrl,
        defaultCurrency,
        timezone,
        language,
        themeMode,
        updatedAt,
      ];
}

/// A row of `public.user_settings` — notification and security preferences,
/// kept separate from the profile so they can be updated independently.
class UserSettings extends Equatable {
  const UserSettings({
    required this.userId,
    this.notifyBudgetWarning = true,
    this.notifyBudgetExceeded = true,
    this.notifyBillDue = true,
    this.notifySubscriptionRenewal = true,
    this.notifyRecurringDue = true,
    this.notifyOcrCompleted = true,
    this.notifyOcrFailed = true,
    this.biometricLockEnabled = false,
    this.appLockTimeoutSeconds = 0,
    this.defaultAccountId,
    this.hideAmountsOnDashboard = false,
    this.requireBiometricToReveal = false,
    this.autoHideOnBackground = true,
    this.revealTimeoutSeconds = 0,
    this.weekStartsMonday = true,
  });

  final String userId;
  final bool notifyBudgetWarning;
  final bool notifyBudgetExceeded;
  final bool notifyBillDue;
  final bool notifySubscriptionRenewal;
  final bool notifyRecurringDue;
  final bool notifyOcrCompleted;
  final bool notifyOcrFailed;

  /// Whether the app asks for a fingerprint or face before it can be used.
  final bool biometricLockEnabled;

  /// How long the app may sit in the background before the lock reappears.
  ///
  /// Zero means lock the moment it leaves the foreground. A grace period
  /// exists because the lock is otherwise unusable in practice: picking a
  /// receipt from the gallery backgrounds the app, and re-authenticating to
  /// get back to the form you were already in teaches people to turn the
  /// whole feature off.
  final int appLockTimeoutSeconds;
  final String? defaultAccountId;

  /// Whether amounts start hidden. This is the persisted default for privacy
  /// mode; the live on/off state for the session is held in a provider, since
  /// tapping the eye should not cost a write.
  final bool hideAmountsOnDashboard;

  /// Whether revealing hidden amounts needs a biometric check.
  ///
  /// Only meaningful with a biometric enrolled; the settings screen keeps it
  /// switched off and disabled otherwise rather than offering a lock with no
  /// key.
  final bool requireBiometricToReveal;

  /// Whether amounts re-hide when the app goes to the background, so they are
  /// not in the task-switcher screenshot.
  final bool autoHideOnBackground;

  /// How long revealed amounts stay visible. Zero means until hidden manually.
  final int revealTimeoutSeconds;
  final bool weekStartsMonday;

  /// Whether any privacy setting is doing something, for the settings subtitle.
  bool get hasPrivacyProtection =>
      hideAmountsOnDashboard || requireBiometricToReveal || biometricLockEnabled;

  bool isEnabled(NotificationKind kind) => switch (kind) {
        NotificationKind.budgetWarning => notifyBudgetWarning,
        NotificationKind.budgetExceeded => notifyBudgetExceeded,
        NotificationKind.billDue => notifyBillDue,
        NotificationKind.subscriptionRenewal => notifySubscriptionRenewal,
        NotificationKind.recurringDue => notifyRecurringDue,
        NotificationKind.ocrCompleted => notifyOcrCompleted,
        NotificationKind.ocrFailed => notifyOcrFailed,
        NotificationKind.goalReached => true,
        NotificationKind.creditCardDue => notifyBillDue,
      };

  factory UserSettings.fromJson(Json json) => UserSettings(
        userId: json.str('user_id'),
        notifyBudgetWarning:
            json.boolVal('notify_budget_warning', fallback: true),
        notifyBudgetExceeded:
            json.boolVal('notify_budget_exceeded', fallback: true),
        notifyBillDue: json.boolVal('notify_bill_due', fallback: true),
        notifySubscriptionRenewal:
            json.boolVal('notify_subscription_renewal', fallback: true),
        notifyRecurringDue:
            json.boolVal('notify_recurring_due', fallback: true),
        notifyOcrCompleted:
            json.boolVal('notify_ocr_completed', fallback: true),
        notifyOcrFailed: json.boolVal('notify_ocr_failed', fallback: true),
        biometricLockEnabled: json.boolVal('biometric_lock_enabled'),
        appLockTimeoutSeconds: json.intVal('app_lock_timeout_seconds'),
        defaultAccountId: json.strOrNull('default_account_id'),
        hideAmountsOnDashboard: json.boolVal('hide_amounts_on_dashboard'),
        requireBiometricToReveal:
            json.boolVal('require_biometric_to_reveal'),
        autoHideOnBackground:
            json.boolVal('auto_hide_on_background', fallback: true),
        revealTimeoutSeconds: json.intVal('reveal_timeout_seconds'),
        weekStartsMonday: json.boolVal('week_starts_monday', fallback: true),
      );

  Json toUpdateJson() => {
        'notify_budget_warning': notifyBudgetWarning,
        'notify_budget_exceeded': notifyBudgetExceeded,
        'notify_bill_due': notifyBillDue,
        'notify_subscription_renewal': notifySubscriptionRenewal,
        'notify_recurring_due': notifyRecurringDue,
        'notify_ocr_completed': notifyOcrCompleted,
        'notify_ocr_failed': notifyOcrFailed,
        'biometric_lock_enabled': biometricLockEnabled,
        'app_lock_timeout_seconds': appLockTimeoutSeconds,
        'default_account_id': defaultAccountId,
        'hide_amounts_on_dashboard': hideAmountsOnDashboard,
        'require_biometric_to_reveal': requireBiometricToReveal,
        'auto_hide_on_background': autoHideOnBackground,
        'reveal_timeout_seconds': revealTimeoutSeconds,
        'week_starts_monday': weekStartsMonday,
      };

  UserSettings copyWith({
    bool? notifyBudgetWarning,
    bool? notifyBudgetExceeded,
    bool? notifyBillDue,
    bool? notifySubscriptionRenewal,
    bool? notifyRecurringDue,
    bool? notifyOcrCompleted,
    bool? notifyOcrFailed,
    bool? biometricLockEnabled,
    int? appLockTimeoutSeconds,
    Object? defaultAccountId = _sentinel,
    bool? hideAmountsOnDashboard,
    bool? requireBiometricToReveal,
    bool? autoHideOnBackground,
    int? revealTimeoutSeconds,
    bool? weekStartsMonday,
  }) =>
      UserSettings(
        userId: userId,
        notifyBudgetWarning: notifyBudgetWarning ?? this.notifyBudgetWarning,
        notifyBudgetExceeded: notifyBudgetExceeded ?? this.notifyBudgetExceeded,
        notifyBillDue: notifyBillDue ?? this.notifyBillDue,
        notifySubscriptionRenewal:
            notifySubscriptionRenewal ?? this.notifySubscriptionRenewal,
        notifyRecurringDue: notifyRecurringDue ?? this.notifyRecurringDue,
        notifyOcrCompleted: notifyOcrCompleted ?? this.notifyOcrCompleted,
        notifyOcrFailed: notifyOcrFailed ?? this.notifyOcrFailed,
        biometricLockEnabled:
            biometricLockEnabled ?? this.biometricLockEnabled,
        appLockTimeoutSeconds:
            appLockTimeoutSeconds ?? this.appLockTimeoutSeconds,
        defaultAccountId: defaultAccountId == _sentinel
            ? this.defaultAccountId
            : defaultAccountId as String?,
        hideAmountsOnDashboard:
            hideAmountsOnDashboard ?? this.hideAmountsOnDashboard,
        requireBiometricToReveal:
            requireBiometricToReveal ?? this.requireBiometricToReveal,
        autoHideOnBackground:
            autoHideOnBackground ?? this.autoHideOnBackground,
        revealTimeoutSeconds:
            revealTimeoutSeconds ?? this.revealTimeoutSeconds,
        weekStartsMonday: weekStartsMonday ?? this.weekStartsMonday,
      );

  static const Object _sentinel = Object();

  @override
  List<Object?> get props => [
        userId,
        notifyBudgetWarning,
        notifyBudgetExceeded,
        notifyBillDue,
        notifySubscriptionRenewal,
        notifyRecurringDue,
        notifyOcrCompleted,
        notifyOcrFailed,
        biometricLockEnabled,
        appLockTimeoutSeconds,
        defaultAccountId,
        hideAmountsOnDashboard,
        requireBiometricToReveal,
        autoHideOnBackground,
        revealTimeoutSeconds,
        weekStartsMonday,
      ];
}
