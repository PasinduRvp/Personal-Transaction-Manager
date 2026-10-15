import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ocr/text_recogniser.dart';
import '../repositories/account_repository.dart';
import '../repositories/account_seeder.dart';
import '../repositories/analytics_repository.dart';
import '../repositories/auth_repository.dart';
import '../repositories/bill_repository.dart';
import '../repositories/budget_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/document_repository.dart';
import '../repositories/lending_repository.dart';
import '../repositories/maintenance_runner.dart';
import '../repositories/notification_repository.dart';
import '../repositories/ocr_repository.dart';
import '../repositories/profile_repository.dart';
import '../repositories/savings_repository.dart';
import '../repositories/transaction_repository.dart';
import 'core_providers.dart';

/// Repository wiring.
///
/// Each repository takes its collaborators as constructor arguments rather than
/// reaching for singletons, so a test can substitute a fake Firestore or storage
/// by overriding one provider.

final accountSeederProvider = Provider<AccountSeeder>(
  (ref) => AccountSeeder(firestore: ref.watch(firestoreProvider)),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    cache: ref.watch(cacheServiceProvider),
    store: ref.watch(documentStoreProvider),
    seeder: ref.watch(accountSeederProvider),
  ),
);

/// The work a scheduler did on the paid plan, run when the app opens.
final maintenanceRunnerProvider = Provider<MaintenanceRunner>(
  (ref) => MaintenanceRunner(firestore: ref.watch(firestoreProvider)),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(
    firestore: ref.watch(firestoreProvider),
    store: ref.watch(documentStoreProvider),
  ),
);

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(
    firestore: ref.watch(firestoreProvider),
  ),
);

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(
    firestore: ref.watch(firestoreProvider),
  ),
);

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepository(
    firestore: ref.watch(firestoreProvider),
  ),
);

final budgetRepositoryProvider = Provider<BudgetRepository>(
  (ref) => BudgetRepository(firestore: ref.watch(firestoreProvider)),
);

final savingsRepositoryProvider = Provider<SavingsRepository>(
  (ref) => SavingsRepository(firestore: ref.watch(firestoreProvider)),
);

final lendingRepositoryProvider = Provider<LendingRepository>(
  (ref) => LendingRepository(firestore: ref.watch(firestoreProvider)),
);

final billRepositoryProvider = Provider<BillRepository>(
  (ref) => BillRepository(firestore: ref.watch(firestoreProvider)),
);

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>(
  (ref) => SubscriptionRepository(firestore: ref.watch(firestoreProvider)),
);

final recurringRepositoryProvider = Provider<RecurringRepository>(
  (ref) => RecurringRepository(firestore: ref.watch(firestoreProvider)),
);

final documentRepositoryProvider = Provider<DocumentRepository>(
  (ref) => DocumentRepository(
    firestore: ref.watch(firestoreProvider),
    store: ref.watch(documentStoreProvider),
  ),
);

final ocrRepositoryProvider = Provider<OcrRepository>((ref) {
  final recogniser = MlKitTextRecogniser();
  // The recogniser holds a native handle, so it is closed when the provider is
  // disposed rather than left for the platform to reclaim.
  ref.onDispose(recogniser.dispose);

  return OcrRepository(
    firestore: ref.watch(firestoreProvider),
    store: ref.watch(documentStoreProvider),
    recogniser: recogniser,
  );
});

final analyticsRepositoryProvider = Provider<AnalyticsRepository>(
  (ref) => AnalyticsRepository(firestore: ref.watch(firestoreProvider)),
);

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(firestore: ref.watch(firestoreProvider)),
);
