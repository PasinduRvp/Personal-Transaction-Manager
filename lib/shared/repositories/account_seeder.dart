import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/firebase_service.dart';
import '../models/json_map.dart';
import 'base_repository.dart';

/// Creates a new user's profile, settings and default categories.
///
/// On the paid plan this was a Cloud Function triggered by the account's first
/// write. Without a server the app has to do it, which raises exactly the problem
/// the function existed to avoid: two devices signing in to a fresh account would
/// each find the data missing and each write a full set, and the user would open
/// the app to every category twice over.
///
/// A Firestore transaction solves it. The profile document is read and written
/// inside one, so of two devices racing, the second sees `seeded_at` already set
/// and does nothing — the transaction retries on conflict and re-reads, which is
/// precisely the behaviour needed. The 22 category writes ride along in the same
/// transaction, so there is no window in which a profile exists without them.
///
/// Called on every sign-in, not only on sign-up. A sign-up whose seeding never ran
/// — the app was killed, or the device was offline — would otherwise leave an
/// account with no profile and no way to get one.
class AccountSeeder extends BaseRepository {
  AccountSeeder({super.firestore});

  /// Seeds the account if it has not been seeded, and does nothing if it has.
  ///
  /// Returns true when this call did the seeding, which the caller uses only for
  /// logging — the app's behaviour is the same either way.
  Future<bool> ensureSeeded({
    String? fullName,
    String? defaultCurrency,
  }) =>
      guard(() async {
        final uid = userId;
        final profileRef = FirebaseService.userDoc(uid);

        // A cheap read first. After the first run this is the only cost, and
        // Firestore usually serves it from the local cache.
        final existing = await profileRef.get();
        if (existing.exists && existing.asJson.dateOrNull('seeded_at') != null) {
          return false;
        }

        final currency = (defaultCurrency != null &&
                defaultCurrency.length == 3)
            ? defaultCurrency.toUpperCase()
            : 'LKR';

        final name = fullName?.trim().isNotEmpty == true
            ? fullName!.trim()
            : (FirebaseService.user?.displayName ?? '');

        final email = FirebaseService.user?.email ?? '';
        final categories = FirebaseService.categories(uid);

        var didSeed = false;

        await db.runTransaction((tx) async {
          final snapshot = await tx.get(profileRef);

          // Re-checked inside the transaction. This is the guard that makes two
          // devices safe: the loser of the race reads the winner's write and stops.
          if (snapshot.exists &&
              snapshot.asJson.dateOrNull('seeded_at') != null) {
            return;
          }

          tx.set(
            profileRef,
            {
              'id': uid,
              'email': email,
              'full_name': name,
              'default_currency': currency,
              'timezone': DateTime.now().timeZoneName,
              'language': 'en',
              'theme': 'SYSTEM',
              // The marker that makes this whole operation idempotent.
              'seeded_at': FieldValue.serverTimestamp(),
              ...createdFields(),
            },
            SetOptions(merge: true),
          );

          tx.set(
            FirebaseService.settingsDoc(uid),
            {
              'user_id': uid,
              'notify_budget_warning': true,
              'notify_budget_exceeded': true,
              'notify_bill_due': true,
              'notify_subscription_renewal': true,
              'notify_recurring_due': true,
              'notify_ocr_completed': true,
              'notify_ocr_failed': true,
              'biometric_lock_enabled': false,
              'hide_amounts_on_dashboard': false,
              'week_starts_monday': true,
              ...createdFields(),
            },
            SetOptions(merge: true),
          );

          for (var index = 0; index < defaultCategories.length; index++) {
            final category = defaultCategories[index];
            tx.set(categories.doc(), {
              'user_id': uid,
              'name': category.name,
              'kind': category.kind,
              'icon': category.icon,
              'color': category.color,
              // System categories may be archived but never deleted: a transaction
              // from two years ago still points at one, and Firestore would not
              // stop the delete that orphaned it.
              'is_system': true,
              'is_archived': false,
              'sort_order': index,
              ...createdFields(),
            });
          }

          didSeed = true;
        });

        if (didSeed) {
          log.info('Seeded a new account with ${defaultCategories.length} '
              'categories');
        }

        return didSeed;
      });

  /// The categories every new account starts with.
  ///
  /// Eighteen expense and four income, chosen to cover ordinary spending in Sri
  /// Lanka without being so many that the picker becomes a scroll. They are
  /// editable and archivable; only deletion is refused.
  static const List<DefaultCategory> defaultCategories = [
    DefaultCategory('Food & Dining', 'EXPENSE', 'restaurant', '#F97066'),
    DefaultCategory('Groceries', 'EXPENSE', 'shopping_cart', '#FDB022'),
    DefaultCategory('Transport', 'EXPENSE', 'directions_bus', '#36BFFA'),
    DefaultCategory('Fuel', 'EXPENSE', 'local_gas_station', '#2E90FA'),
    DefaultCategory('Shopping', 'EXPENSE', 'shopping_bag', '#EE46BC'),
    DefaultCategory('Bills & Utilities', 'EXPENSE', 'receipt_long', '#7A5AF8'),
    DefaultCategory('Rent', 'EXPENSE', 'home', '#875BF7'),
    DefaultCategory('Health', 'EXPENSE', 'favorite', '#F63D68'),
    DefaultCategory('Education', 'EXPENSE', 'school', '#0BA5EC'),
    DefaultCategory('Entertainment', 'EXPENSE', 'movie', '#FB6514'),
    DefaultCategory('Subscriptions', 'EXPENSE', 'autorenew', '#6172F3'),
    DefaultCategory('Travel', 'EXPENSE', 'flight', '#15B79E'),
    DefaultCategory('Personal Care', 'EXPENSE', 'spa', '#EE46BC'),
    DefaultCategory('Gifts & Donations', 'EXPENSE', 'card_giftcard', '#F670C7'),
    DefaultCategory('Insurance', 'EXPENSE', 'shield', '#4E5BA6'),
    DefaultCategory('Taxes', 'EXPENSE', 'account_balance', '#667085'),
    DefaultCategory('Fees & Charges', 'EXPENSE', 'payments', '#98A2B3'),
    DefaultCategory('Other', 'EXPENSE', 'more_horiz', '#98A2B3'),
    DefaultCategory('Salary', 'INCOME', 'work', '#12B76A'),
    DefaultCategory('Business', 'INCOME', 'storefront', '#039855'),
    DefaultCategory('Interest', 'INCOME', 'savings', '#32D583'),
    DefaultCategory('Other Income', 'INCOME', 'add_circle', '#6CE9A6'),
  ];
}

class DefaultCategory {
  const DefaultCategory(this.name, this.kind, this.icon, this.color);

  final String name;
  final String kind;
  final String icon;
  final String color;
}
