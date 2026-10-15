import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _log = Logger('Cache');

/// A cached value plus the time it was written.
class CachedValue<T> {
  const CachedValue(this.value, this.savedAt);

  final T value;
  final DateTime savedAt;

  Duration get age => DateTime.now().difference(savedAt);
  bool isStale(Duration maxAge) => age > maxAge;
}

/// A small read-through cache for the data the app must still show offline:
/// the dashboard snapshot, accounts, categories and the first page of
/// transactions.
///
/// Values are namespaced per user id so signing into a different account on the
/// same device can never surface the previous user's financial data. Clearing
/// happens on sign-out.
class CacheService {
  CacheService(this._prefs);

  final SharedPreferences _prefs;

  static const String _prefix = 'finora_cache';

  static Future<CacheService> create() async =>
      CacheService(await SharedPreferences.getInstance());

  String _key(String userId, String name) => '$_prefix:$userId:$name';

  /// Cache keys. Grouped here so `clearForUser` can find them all.
  static const String keyDashboard = 'dashboard';
  static const String keyAccounts = 'accounts';
  static const String keyCategories = 'categories';
  static const String keyRecentTransactions = 'recent_transactions';
  static const String keyProfile = 'profile';
  static const String keySettings = 'settings';
  static const String keyPendingWrites = 'pending_writes';

  static const List<String> _allKeys = [
    keyDashboard,
    keyAccounts,
    keyCategories,
    keyRecentTransactions,
    keyProfile,
    keySettings,
    keyPendingWrites,
  ];

  Future<void> writeJson(
    String userId,
    String name,
    Object payload,
  ) async {
    try {
      final envelope = jsonEncode({
        'saved_at': DateTime.now().toIso8601String(),
        'payload': payload,
      });
      await _prefs.setString(_key(userId, name), envelope);
    } on Object catch (error, stack) {
      // A cache write must never break a working screen.
      _log.warning('Cache write failed for $name', error, stack);
    }
  }

  CachedValue<Map<String, dynamic>>? readMap(String userId, String name) {
    final raw = _prefs.getString(_key(userId, name));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.tryParse(decoded['saved_at'] as String? ?? '');
      final payload = decoded['payload'];
      if (savedAt == null || payload is! Map) return null;
      return CachedValue(Map<String, dynamic>.from(payload), savedAt);
    } on Object catch (error) {
      _log.fine('Discarding unreadable cache entry $name', error);
      return null;
    }
  }

  CachedValue<List<Map<String, dynamic>>>? readList(
    String userId,
    String name,
  ) {
    final raw = _prefs.getString(_key(userId, name));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.tryParse(decoded['saved_at'] as String? ?? '');
      final payload = decoded['payload'];
      if (savedAt == null || payload is! List) return null;
      return CachedValue(
        payload
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
        savedAt,
      );
    } on Object catch (error) {
      _log.fine('Discarding unreadable cache entry $name', error);
      return null;
    }
  }

  Future<void> remove(String userId, String name) =>
      _prefs.remove(_key(userId, name));

  /// Wipes every cached value for a user. Called on sign-out and on account
  /// deletion so no financial data is left on the device.
  Future<void> clearForUser(String userId) async {
    for (final name in _allKeys) {
      await _prefs.remove(_key(userId, name));
    }
  }

  /// Defensive sweep for any Finora cache key, used when the signed-in user is
  /// unknown (e.g. recovering from a corrupted session).
  Future<void> clearAll() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }
}
