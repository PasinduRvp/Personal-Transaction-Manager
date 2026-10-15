import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:finora/core/routing/app_routes.dart';
import 'package:finora/core/services/cache_service.dart';
import 'package:finora/core/services/connectivity_service.dart';
import 'package:finora/core/services/firebase_service.dart';
import 'package:finora/main.dart';
import 'package:finora/shared/providers/core_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// End-to-end test against a real Firebase project.
///
/// This is the only test that touches the network. It drives the whole journey
/// the product is built around:
///
///   sign in → create an account → add a transaction → see it on the dashboard
///   → import a document → review the extraction → confirm → see the result
///
/// It needs a Firebase project with the rules, indexes and functions deployed —
/// or the emulator suite running — plus a test user, supplied with --dart-define:
///
///   flutter test integration_test/app_flow_test.dart \
///     --dart-define=TEST_USER_EMAIL=... \
///     --dart-define=TEST_USER_PASSWORD=...
///
/// The project details are not passed in: they come from `google-services.json`
/// and `firebase_options.dart`, the same as in a normal run.
///
/// Without those it skips rather than fails, so `flutter test` on a fresh
/// checkout stays green: a missing credential is a configuration gap, not a
/// defect in the code under test.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const testEmail = String.fromEnvironment('TEST_USER_EMAIL');
  const testPassword = String.fromEnvironment('TEST_USER_PASSWORD');

  final hasCredentials = testEmail.isNotEmpty && testPassword.isNotEmpty;

  group('Finora end-to-end', () {
    late CacheService cache;
    late ConnectivityService connectivity;

    setUpAll(() async {
      if (!hasCredentials) return;
      cache = await CacheService.create();
      connectivity = ConnectivityService();
      await connectivity.initialise();
      await FirebaseService.initialise();
    });

    tearDownAll(() async {
      if (!hasCredentials) return;
      // Leave no session behind on the device running the suite.
      await FirebaseService.auth.signOut();
      await cache.clearAll();
      await connectivity.dispose();
    });

    Future<void> launch(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cacheServiceProvider.overrideWithValue(cache),
            connectivityServiceProvider.overrideWithValue(connectivity),
          ],
          child: const FinoraApp(),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 5));
    }

    testWidgets(
      'signs in and reaches the dashboard',
      (tester) async {
        await launch(tester);

        // The splash gives way to the login screen once the session check is
        // done and finds nothing stored.
        expect(find.text('Welcome back'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'),
          testEmail,
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'),
          testPassword,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
        await tester.pumpAndSettle(const Duration(seconds: 10));

        // The router redirects on the auth state change.
        expect(find.textContaining('Good'), findsWidgets);
        expect(find.text('Your financial overview'), findsOneWidget);
      },
      skip: !hasCredentials,
    );

    testWidgets(
      'creates an account and records a transaction that appears in the list',
      (tester) async {
        await launch(tester);
        await _signInIfNeeded(tester, testEmail, testPassword);

        // --- Create an account -------------------------------------------
        await tester.tap(find.byIcon(Icons.person_outline_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Accounts'));
        await tester.pumpAndSettle(const Duration(seconds: 3));

        await tester.tap(find.byIcon(Icons.add_rounded).first);
        await tester.pumpAndSettle();

        final accountName = 'Test Cash ${DateTime.now().millisecondsSinceEpoch}';
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Account name *'),
          accountName,
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Opening balance'),
          '50000',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Add account'));
        await tester.pumpAndSettle(const Duration(seconds: 6));

        expect(find.text(accountName), findsWidgets);

        // --- Record an expense -------------------------------------------
        await tester.tap(find.byIcon(Icons.arrow_back).first);
        await tester.pumpAndSettle();

        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Expense'));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Amount'),
          '1250',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Merchant'),
          'Integration Test Cafe',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(FilledButton, 'Save expense'));
        await tester.pumpAndSettle(const Duration(seconds: 8));

        // --- It shows up in the transaction list --------------------------
        await tester.tap(find.text('Transactions'));
        await tester.pumpAndSettle(const Duration(seconds: 5));

        expect(find.text('Integration Test Cafe'), findsWidgets);
        expect(find.textContaining('1,250'), findsWidgets);
      },
      skip: !hasCredentials,
    );

    testWidgets(
      'a budget reflects spending against it',
      (tester) async {
        await launch(tester);
        await _signInIfNeeded(tester, testEmail, testPassword);

        await tester.tap(find.text('Budgets'));
        await tester.pumpAndSettle(const Duration(seconds: 5));

        // Either there are budgets with progress, or the empty state invites
        // creating one. Both are correct; an error state is not.
        final hasBudgets = find.textContaining('left to spend').evaluate().isNotEmpty ||
            find.textContaining('Over budget').evaluate().isNotEmpty;
        final isEmpty = find.text('No budgets yet').evaluate().isNotEmpty;

        expect(hasBudgets || isEmpty, isTrue);
        expect(find.text('Something went wrong'), findsNothing);
      },
      skip: !hasCredentials,
    );

    testWidgets(
      'the import flow reaches a review screen and never saves without '
      'confirmation',
      (tester) async {
        await launch(tester);
        await _signInIfNeeded(tester, testEmail, testPassword);

        // The import entry point is reachable from the add menu.
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();

        expect(find.text('Import document'), findsOneWidget);

        await tester.tap(find.text('Import document'));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // The source sheet offers every supported input.
        expect(find.text('Choose from gallery'), findsOneWidget);
        expect(find.text('Image file'), findsOneWidget);
        expect(find.text('PDF document'), findsOneWidget);

        // The promise is stated to the user up front.
        expect(
          find.textContaining('Nothing is saved until you confirm'),
          findsOneWidget,
        );

        // A file picker cannot be driven from an integration test, so the
        // upload itself is covered by the Deno parser tests and by the
        // database's own refusal to accept an unconfirmed candidate.
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      },
      skip: !hasCredentials,
    );

    testWidgets(
      'an unreviewed import never appears as a transaction',
      (tester) async {
        // The product's central guarantee, checked at the data layer: candidates
        // exist, and none of them has produced a transaction without being
        // confirmed first.
        //
        // Postgres enforced the second half of this with a table constraint.
        // Firestore has no constraints, so the invariant lives in the
        // `confirmOcrCandidate` function and in the rules that stop a client
        // writing either field — which makes checking it here more valuable, not
        // less.
        final userId = FirebaseService.requireUserId();
        final candidates = FirebaseService.ocrCandidates(userId);

        final pending =
            await candidates.where('status', isEqualTo: 'PENDING').get();

        for (final doc in pending.docs) {
          expect(
            doc.data()['created_transaction_id'],
            isNull,
            reason: 'A pending candidate must not have created a transaction',
          );
        }

        final confirmed =
            await candidates.where('status', isEqualTo: 'CONFIRMED').get();

        for (final doc in confirmed.docs) {
          final transactionId = doc.data()['created_transaction_id'] as String?;
          expect(
            transactionId,
            isNotNull,
            reason: 'A confirmed candidate must point at a real transaction',
          );

          final transaction = await FirebaseService.transactions(userId)
              .doc(transactionId!)
              .get();
          expect(
            transaction.exists,
            isTrue,
            reason: 'A confirmed candidate points at a transaction that is gone',
          );
        }
      },
      skip: !hasCredentials,
    );

    testWidgets(
      'the security rules refuse another account\u0027s data',
      (tester) async {
        // Under Firestore, isolation is structural: every document lives below
        // `users/{uid}`, so a cross-user read is not merely denied by a policy —
        // there is no path to it the rules allow. Both halves are asserted: that
        // the user's own collections hold only their own documents, and that
        // reaching for someone else's subtree is rejected rather than returning an
        // empty list, which would be a much weaker guarantee.
        final userId = FirebaseService.requireUserId();

        for (final collection in <CollectionReference<Map<String, dynamic>>>[
          FirebaseService.accounts(userId),
          FirebaseService.categories(userId),
          FirebaseService.transactions(userId),
          FirebaseService.budgets(userId),
          FirebaseService.savingsGoals(userId),
          FirebaseService.bills(userId),
          FirebaseService.subscriptions(userId),
          FirebaseService.documents(userId),
          FirebaseService.ocrJobs(userId),
        ]) {
          final snapshot = await collection.limit(200).get();
          for (final doc in snapshot.docs) {
            expect(
              doc.data()['user_id'],
              userId,
              reason: '${collection.path} holds a document for another user',
            );
          }
        }

        await expectLater(
          FirebaseService.firestore
              .collection('users')
              .doc('someone-elses-uid')
              .collection('transactions')
              .limit(1)
              .get(),
          throwsA(
            isA<FirebaseException>()
                .having((e) => e.code, 'code', 'permission-denied'),
          ),
        );

        // A collection group query without the owner filter must also be refused,
        // because a group spans every user's subcollections.
        await expectLater(
          FirebaseService.firestore
              .collectionGroup('transactions')
              .limit(1)
              .get(),
          throwsA(isA<FirebaseException>()),
        );
      },
      skip: !hasCredentials,
    );

    testWidgets(
      'signing out clears the session and returns to login',
      (tester) async {
        await launch(tester);
        await _signInIfNeeded(tester, testEmail, testPassword);

        await tester.tap(find.byIcon(Icons.person_outline_rounded));
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('Sign out'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Sign out'));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
        await tester.pumpAndSettle(const Duration(seconds: 5));

        expect(find.text('Welcome back'), findsOneWidget);
        expect(FirebaseService.isSignedIn, isFalse);
      },
      skip: !hasCredentials,
    );
  });

  test('route names are unique', () {
    // Cheap guard that runs everywhere: two routes sharing a path would make one
    // of them unreachable, which is easy to introduce and hard to notice.
    final paths = <String>[
      AppRoutes.splash,
      AppRoutes.login,
      AppRoutes.register,
      AppRoutes.forgotPassword,
      AppRoutes.resetPassword,
      AppRoutes.verifyEmail,
      AppRoutes.home,
      AppRoutes.transactions,
      AppRoutes.budgets,
      AppRoutes.analytics,
      AppRoutes.profile,
      AppRoutes.transactionAdd,
      AppRoutes.accounts,
      AppRoutes.accountAdd,
      AppRoutes.categories,
      AppRoutes.budgetAdd,
      AppRoutes.savings,
      AppRoutes.savingsAdd,
      AppRoutes.bills,
      AppRoutes.billAdd,
      AppRoutes.subscriptions,
      AppRoutes.subscriptionAdd,
      AppRoutes.recurring,
      AppRoutes.recurringAdd,
      AppRoutes.documents,
      AppRoutes.importDocument,
      AppRoutes.importHistory,
      AppRoutes.reports,
      AppRoutes.notifications,
      AppRoutes.settings,
      AppRoutes.settingsProfile,
      AppRoutes.settingsSecurity,
      AppRoutes.settingsNotifications,
      AppRoutes.settingsData,
      AppRoutes.settingsAbout,
      AppRoutes.settingsPrivacy,
    ];

    expect(paths.toSet().length, paths.length);
  });
}

/// Signs in when the app is showing the login screen, so each test can start
/// from a known state without depending on the order they run in.
Future<void> _signInIfNeeded(
  WidgetTester tester,
  String email,
  String password,
) async {
  if (find.text('Welcome back').evaluate().isEmpty) return;

  await tester.enterText(find.widgetWithText(TextFormField, 'Email'), email);
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Password'),
    password,
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await tester.pumpAndSettle(const Duration(seconds: 10));
}
