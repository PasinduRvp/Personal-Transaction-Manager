import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/accounts/presentation/account_detail_screen.dart';
import '../../features/accounts/presentation/account_form_screen.dart';
import '../../features/accounts/presentation/accounts_screen.dart';
import '../../features/analytics/presentation/analytics_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/recovery_screens.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/bills/presentation/bill_form_screen.dart';
import '../../features/bills/presentation/bills_screen.dart';
import '../../features/budgets/presentation/budget_form_screen.dart';
import '../../features/budgets/presentation/budgets_screen.dart';
import '../../features/categories/presentation/categories_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/documents/presentation/documents_screen.dart';
import '../../features/documents/presentation/import_history_screen.dart';
import '../../features/lending/presentation/lending_detail_screen.dart';
import '../../features/lending/presentation/lending_form_screen.dart';
import '../../features/lending/presentation/lending_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/ocr/presentation/import_processing_screen.dart';
import '../../features/ocr/presentation/ocr_review_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/settings_pages.dart';
import '../../features/profile/presentation/settings_screen.dart';
import '../../features/recurring/presentation/recurring_form_screen.dart';
import '../../features/recurring/presentation/recurring_screen.dart';
import '../../features/reports/presentation/reports_screen.dart';
import '../../features/savings/presentation/savings_detail_screen.dart';
import '../../features/savings/presentation/savings_form_screen.dart';
import '../../features/savings/presentation/savings_screen.dart';
import '../../features/subscriptions/presentation/subscription_form_screen.dart';
import '../../features/subscriptions/presentation/subscriptions_screen.dart';
import '../../features/transactions/presentation/split_transaction_screen.dart';
import '../../features/transactions/presentation/transaction_detail_screen.dart';
import '../../features/transactions/presentation/transaction_form_screen.dart';
import '../../features/transactions/presentation/transactions_screen.dart';
import '../../shared/providers/auth_providers.dart';
import '../constants/enums.dart';
import '../utils/app_date_utils.dart';
import 'app_routes.dart';
import 'app_shell.dart';

/// The router.
///
/// Authentication is handled by one `redirect` rather than by each screen
/// checking for itself: a missed check on a single screen would be a hole in the
/// app, and a central rule cannot be forgotten. RLS refuses the data anyway, so
/// this is about not showing an empty broken screen rather than about secrecy.
final routerProvider = Provider<GoRouter>((ref) {
  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  final shellKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

  // Refreshes the redirect whenever authentication changes, so a sign-out
  // anywhere immediately moves the user to the login screen.
  final refresh = _AuthRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    debugLogDiagnostics: false,

    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;
      final isPublic = AppRoutes.publicRoutes.contains(location);

      switch (auth.status) {
        case AuthStatus.unknown:
          // Session still restoring: hold on the splash screen.
          return location == AppRoutes.splash ? null : AppRoutes.splash;

        case AuthStatus.awaitingVerification:
          // Signed in but unverified: the app's data screens need a verified
          // address, since that is the only account-recovery path.
          return location == AppRoutes.verifyEmail
              ? null
              : AppRoutes.verifyEmail;

        case AuthStatus.unauthenticated:
          return isPublic && location != AppRoutes.splash
              ? null
              : AppRoutes.login;

        case AuthStatus.authenticated:
          // Signed in: keep them out of the auth screens.
          return isPublic ? AppRoutes.home : null;
      }
    },

    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (context, state) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.verifyEmail,
        builder: (context, state) => VerifyEmailScreen(
          email: state.uri.queryParameters['email'],
        ),
      ),

      // --- The five tabs ---------------------------------------------------
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: shellKey,
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.transactions,
                builder: (context, state) => const TransactionsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.budgets,
                builder: (context, state) => const BudgetsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.analytics,
                builder: (context, state) => const AnalyticsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),

      // --- Pushed over the shell -------------------------------------------
      // These sit outside the branches so they cover the bottom navigation,
      // which is right for a focused task like entering a transaction.

      GoRoute(
        path: AppRoutes.transactionAdd,
        parentNavigatorKey: rootKey,
        builder: (context, state) => TransactionFormScreen(
          initialType: TransactionType.fromWire(
            state.uri.queryParameters['type'],
          ),
          initialToAccountId: state.uri.queryParameters['toAccount'],
        ),
      ),
      GoRoute(
        path: '/transactions/:id',
        parentNavigatorKey: rootKey,
        builder: (context, state) => TransactionDetailScreen(
          transactionId: state.pathParameters['id']!,
        ),
        routes: [
          GoRoute(
            path: 'edit',
            parentNavigatorKey: rootKey,
            builder: (context, state) => TransactionFormScreen(
              transactionId: state.pathParameters['id'],
            ),
          ),
          GoRoute(
            path: 'split',
            parentNavigatorKey: rootKey,
            builder: (context, state) => SplitTransactionScreen(
              transactionId: state.pathParameters['id']!,
            ),
          ),
        ],
      ),

      GoRoute(
        path: AppRoutes.accounts,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const AccountsScreen(),
      ),
      GoRoute(
        path: AppRoutes.accountAdd,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const AccountFormScreen(),
      ),
      GoRoute(
        path: '/accounts/:id',
        parentNavigatorKey: rootKey,
        builder: (context, state) => AccountDetailScreen(
          accountId: state.pathParameters['id']!,
        ),
        routes: [
          GoRoute(
            path: 'edit',
            parentNavigatorKey: rootKey,
            builder: (context, state) => AccountFormScreen(
              accountId: state.pathParameters['id'],
            ),
          ),
        ],
      ),

      GoRoute(
        path: AppRoutes.categories,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const CategoriesScreen(),
      ),

      GoRoute(
        path: AppRoutes.budgetAdd,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const BudgetFormScreen(),
      ),
      GoRoute(
        path: '/budgets/:id',
        parentNavigatorKey: rootKey,
        redirect: (context, state) =>
            AppRoutes.budgetEdit(state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/budgets/:id/edit',
        parentNavigatorKey: rootKey,
        builder: (context, state) => BudgetFormScreen(
          budgetId: state.pathParameters['id'],
        ),
      ),

      GoRoute(
        path: AppRoutes.savings,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const SavingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.savingsAdd,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const SavingsFormScreen(),
      ),
      GoRoute(
        path: '/savings/:id',
        parentNavigatorKey: rootKey,
        builder: (context, state) => SavingsDetailScreen(
          goalId: state.pathParameters['id']!,
        ),
        routes: [
          GoRoute(
            path: 'edit',
            parentNavigatorKey: rootKey,
            builder: (context, state) => SavingsFormScreen(
              goalId: state.pathParameters['id'],
            ),
          ),
        ],
      ),

      GoRoute(
        path: AppRoutes.lending,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const LendingScreen(),
      ),
      GoRoute(
        path: AppRoutes.lendingAdd,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const LendingFormScreen(),
      ),
      GoRoute(
        path: '/lending/:id',
        parentNavigatorKey: rootKey,
        builder: (context, state) => LendingDetailScreen(
          lendingId: state.pathParameters['id']!,
        ),
      ),

      GoRoute(
        path: AppRoutes.bills,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const BillsScreen(),
      ),
      GoRoute(
        path: AppRoutes.billAdd,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const BillFormScreen(),
      ),
      GoRoute(
        path: '/bills/:id/edit',
        parentNavigatorKey: rootKey,
        builder: (context, state) => BillFormScreen(
          billId: state.pathParameters['id'],
        ),
      ),

      GoRoute(
        path: AppRoutes.subscriptions,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const SubscriptionsScreen(),
      ),
      GoRoute(
        path: AppRoutes.subscriptionAdd,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const SubscriptionFormScreen(),
      ),
      GoRoute(
        path: '/subscriptions/:id/edit',
        parentNavigatorKey: rootKey,
        builder: (context, state) => SubscriptionFormScreen(
          subscriptionId: state.pathParameters['id'],
        ),
      ),

      GoRoute(
        path: AppRoutes.recurring,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const RecurringScreen(),
      ),
      GoRoute(
        path: AppRoutes.recurringAdd,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const RecurringFormScreen(),
      ),
      GoRoute(
        path: '/recurring/:id/edit',
        parentNavigatorKey: rootKey,
        builder: (context, state) => RecurringFormScreen(
          recurringId: state.pathParameters['id'],
        ),
      ),

      // --- Documents and OCR ------------------------------------------------
      GoRoute(
        path: AppRoutes.documents,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const DocumentsScreen(),
      ),
      GoRoute(
        path: AppRoutes.importDocument,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const ImportProcessingScreen(),
      ),
      GoRoute(
        path: AppRoutes.importHistory,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const ImportHistoryScreen(),
      ),
      GoRoute(
        path: '/documents/:id',
        parentNavigatorKey: rootKey,
        builder: (context, state) => DocumentDetailScreen(
          documentId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/ocr/review/:jobId',
        parentNavigatorKey: rootKey,
        builder: (context, state) => OcrReviewEntryScreen(
          jobId: state.pathParameters['jobId']!,
        ),
      ),

      GoRoute(
        path: AppRoutes.reports,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const ReportsScreen(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const NotificationsScreen(),
      ),

      // --- Settings ----------------------------------------------------------
      GoRoute(
        path: AppRoutes.settings,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.settingsProfile,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const ProfileEditScreen(),
      ),
      GoRoute(
        path: AppRoutes.settingsSecurity,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const SecuritySettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.settingsNotifications,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const NotificationSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.settingsData,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const DataSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.settingsAbout,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const AboutScreen(),
      ),
      GoRoute(
        path: AppRoutes.settingsPrivacy,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const PrivacyScreen(),
      ),
    ],

    errorBuilder: (context, state) => _RouteNotFoundScreen(
      location: state.uri.toString(),
    ),
  );
});

/// Bridges Riverpod's auth state to GoRouter's `refreshListenable`.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    _subscription = ref.listen<AuthState>(
      authControllerProvider,
      // Only a status change matters to routing; a token refresh that leaves the
      // user authenticated should not trigger a redirect pass.
      (previous, next) {
        if (previous?.status != next.status) notifyListeners();
      },
      fireImmediately: true,
    );
  }

  late final ProviderSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}

class _RouteNotFoundScreen extends StatelessWidget {
  const _RouteNotFoundScreen({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.explore_off_outlined, size: 48),
              const SizedBox(height: 20),
              Text(
                'That page does not exist',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                location,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go(AppRoutes.home),
                child: const Text('Go home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Parses the `from`/`to` query parameters used by dashboard drill-throughs.
DateRange? dateRangeFromQuery(Map<String, String> query) {
  final from = DateTime.tryParse(query['from'] ?? '');
  final to = DateTime.tryParse(query['to'] ?? '');
  if (from == null || to == null) return null;
  return DateRange(
    AppDateUtils.startOfDay(from),
    AppDateUtils.endOfDay(to),
  );
}
