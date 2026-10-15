/// Every route path and name in one place.
///
/// Referring to `AppRoutes.transactionDetail` rather than a literal string means
/// a renamed route is a compile error instead of a dead link discovered by a
/// user.
class AppRoutes {
  const AppRoutes._();

  // --- Unauthenticated ---------------------------------------------------
  static const String splash = '/splash';
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';
  static const String verifyEmail = '/verify-email';

  // --- Shell tabs ---------------------------------------------------------
  static const String home = '/home';
  static const String transactions = '/transactions';
  static const String budgets = '/budgets';
  static const String analytics = '/analytics';
  static const String profile = '/profile';

  // --- Transactions -------------------------------------------------------
  static const String transactionAdd = '/transactions/add';
  static const String transactionSearch = '/transactions/search';

  static String transactionDetail(String id) => '/transactions/$id';
  static String transactionEdit(String id) => '/transactions/$id/edit';
  static String transactionSplit(String id) => '/transactions/$id/split';

  // --- Accounts -----------------------------------------------------------
  static const String accounts = '/accounts';
  static const String accountAdd = '/accounts/add';

  static String accountDetail(String id) => '/accounts/$id';
  static String accountEdit(String id) => '/accounts/$id/edit';

  // --- Categories ---------------------------------------------------------
  static const String categories = '/categories';

  // --- Budgets ------------------------------------------------------------
  static const String budgetAdd = '/budgets/add';

  static String budgetDetail(String id) => '/budgets/$id';
  static String budgetEdit(String id) => '/budgets/$id/edit';

  // --- Savings ------------------------------------------------------------
  static const String savings = '/savings';
  static const String savingsAdd = '/savings/add';

  static String savingsDetail(String id) => '/savings/$id';
  static String savingsEdit(String id) => '/savings/$id/edit';

  // --- Bills, subscriptions, recurring ------------------------------------
  static const String bills = '/bills';
  static const String billAdd = '/bills/add';
  static const String subscriptions = '/subscriptions';
  static const String subscriptionAdd = '/subscriptions/add';
  static const String recurring = '/recurring';
  static const String recurringAdd = '/recurring/add';

  static String billEdit(String id) => '/bills/$id/edit';
  static String subscriptionEdit(String id) => '/subscriptions/$id/edit';
  static String recurringEdit(String id) => '/recurring/$id/edit';

  // --- Documents and OCR --------------------------------------------------
  static const String documents = '/documents';
  static const String importDocument = '/documents/import';
  static const String importHistory = '/documents/history';
  static const String ocrReview = '/ocr/review';

  static String documentDetail(String id) => '/documents/$id';
  static String ocrProcessing(String jobId) => '/ocr/processing/$jobId';
  static String ocrReviewJob(String jobId) => '/ocr/review/$jobId';

  // --- Reports and notifications -----------------------------------------
  static const String reports = '/reports';
  static const String notifications = '/notifications';

  // --- Settings -----------------------------------------------------------
  static const String settings = '/settings';
  static const String settingsProfile = '/settings/profile';
  static const String settingsSecurity = '/settings/security';
  static const String settingsNotifications = '/settings/notifications';
  static const String settingsData = '/settings/data';
  static const String settingsAbout = '/settings/about';
  static const String settingsPrivacy = '/settings/privacy';

  /// Routes reachable without a verified session.
  static const Set<String> publicRoutes = {
    splash,
    login,
    register,
    forgotPassword,
    resetPassword,
    verifyEmail,
  };
}
