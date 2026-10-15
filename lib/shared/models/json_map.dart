import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/money.dart';

/// Typed, defensive readers for Firestore documents.
///
/// Two conventions this file establishes, both deliberate:
///
/// **Field names stay snake_case.** camelCase is the more common Firestore
/// style, but these names already match the models, the Cloud Functions and the
/// documentation, and renaming several hundred string literals would be a large
/// mechanical change with nothing to show for it. Consistency across the three
/// languages matters more than matching a convention.
///
/// **Money is stored as an integer count of minor units**, in a field suffixed
/// `_minor`. Firestore has no decimal type, so a monetary `double` would
/// reintroduce exactly the representation error [Money] exists to prevent — and
/// unlike Postgres there is no `numeric(16,2)` to fall back on. `845000` with a
/// sibling `currency` of `LKR` is `Rs. 8,450.00`. The suffix is there so nobody
/// reading the console mistakes the figure for rupees.
typedef Json = Map<String, dynamic>;

/// Turns a document into the map the models' `fromJson` expects.
///
/// Firestore keeps the document id outside the data, so it is folded in here
/// rather than every repository remembering to.
extension SnapshotJson on DocumentSnapshot<Map<String, dynamic>> {
  Json get asJson => <String, dynamic>{...?data(), 'id': id};
}

extension QuerySnapshotJson on QuerySnapshot<Map<String, dynamic>> {
  List<Json> get asJsonList => docs.map((doc) => doc.asJson).toList();
}

extension JsonReader on Json {
  String str(String key, {String fallback = ''}) {
    final v = this[key];
    if (v == null) return fallback;
    return v is String ? v : v.toString();
  }

  String? strOrNull(String key) {
    final v = this[key];
    if (v == null) return null;
    final s = v is String ? v : v.toString();
    return s.isEmpty ? null : s;
  }

  int intVal(String key, {int fallback = 0}) {
    final v = this[key];
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  int? intOrNull(String key) {
    final v = this[key];
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  double dbl(String key, {double fallback = 0}) {
    final v = this[key];
    if (v == null) return fallback;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  double? dblOrNull(String key) {
    final v = this[key];
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  bool boolVal(String key, {bool fallback = false}) {
    final v = this[key];
    if (v == null) return fallback;
    if (v is bool) return v;
    final s = v.toString().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return fallback;
  }

  /// Reads a date. Accepts a Firestore [Timestamp], a [DateTime], an ISO string
  /// or epoch milliseconds.
  ///
  /// The string and millisecond cases are not hypothetical: a value written by a
  /// Cloud Function through the Admin SDK, or round-tripped through a callable's
  /// JSON response, arrives as one of those rather than as a Timestamp.
  DateTime dateVal(String key, {DateTime? fallback}) =>
      dateOrNull(key) ?? fallback ?? DateTime.now();

  DateTime? dateOrNull(String key) {
    final v = this[key];
    if (v == null) return null;
    if (v is Timestamp) return v.toDate().toLocal();
    if (v is DateTime) return v.toLocal();
    if (v is int) {
      return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true).toLocal();
    }
    final parsed = DateTime.tryParse(v.toString());
    return parsed?.toLocal();
  }

  /// Reads a monetary field stored as minor units.
  ///
  /// `money('amount')` reads the integer `amount_minor` and the sibling
  /// `currency`. Callers name the logical field, not the stored one.
  Money money(
    String key, {
    String currencyKey = 'currency',
    String fallbackCurrency = 'LKR',
  }) {
    final code = strOrNull(currencyKey) ?? fallbackCurrency;
    return Money.fromMinorUnits(intVal(minorKey(key)), code);
  }

  Money? moneyOrNull(
    String key, {
    String currencyKey = 'currency',
    String fallbackCurrency = 'LKR',
  }) {
    final raw = intOrNull(minorKey(key));
    if (raw == null) return null;
    final code = strOrNull(currencyKey) ?? fallbackCurrency;
    return Money.fromMinorUnits(raw, code);
  }

  /// Reads a nested map field.
  Json jsonVal(String key) {
    final v = this[key];
    if (v == null) return <String, dynamic>{};
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String && v.isNotEmpty) {
      try {
        final decoded = jsonDecode(v);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } on FormatException {
        return <String, dynamic>{};
      }
    }
    return <String, dynamic>{};
  }

  List<String> stringList(String key) {
    final v = this[key];
    if (v is List) return v.map((e) => e.toString()).toList();
    return const [];
  }

  /// Reads a related document that a repository joined in.
  ///
  /// Firestore has no joins, so a repository fetches accounts and categories
  /// once, builds a lookup, and attaches the matching map under this key before
  /// handing the data to the model. The alternative — one read per row — would
  /// turn a 20-row transaction list into 60 billed reads.
  Json? relation(String key) {
    final v = this[key];
    if (v == null) return null;
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is List && v.isNotEmpty && v.first is Map) {
      return Map<String, dynamic>.from(v.first as Map);
    }
    return null;
  }

  List<Json> relationList(String key) {
    final v = this[key];
    if (v is List) {
      return v
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }
}

/// The stored field name for a logical money field.
String minorKey(String key) => '${key}_minor';

/// Writes a monetary field as minor units plus its currency.
///
/// Spread into a document map: `{...moneyFields('amount', amount), …}`.
Json moneyFields(String key, Money? amount, {bool withCurrency = true}) {
  if (amount == null) return <String, dynamic>{};
  return <String, dynamic>{
    minorKey(key): amount.minorUnits,
    if (withCurrency) 'currency': amount.currency,
  };
}

/// Drops null values so a partial update never clears a field unintentionally.
/// [Patch.clear] opts in to writing a null.
Json compactJson(Json source) {
  final result = <String, dynamic>{};
  source.forEach((key, value) {
    if (value == null) return;
    result[key] = value == Patch.clear ? null : value;
  });
  return result;
}

/// Sentinel meaning "set this field to null" in a partial update.
class Patch {
  const Patch._();
  static const Object clear = _ClearSentinel();
}

class _ClearSentinel {
  const _ClearSentinel();
  @override
  String toString() => 'Patch.clear';
}

/// Server-assigned timestamps for create and update.
///
/// `FieldValue.serverTimestamp()` rather than `DateTime.now()`: a device clock
/// can be wrong by hours, and a transaction list ordered by a client-set time
/// would be wrong with it.
Json createdFields() => <String, dynamic>{
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };

Json updatedFields() => <String, dynamic>{
      'updated_at': FieldValue.serverTimestamp(),
    };

/// A date with no meaningful time, stored as an ISO `yyyy-MM-dd` string.
///
/// Due dates, target dates and period bounds are calendar dates, not instants.
/// Storing them as a Timestamp would make them shift across time zones, so a
/// bill due on the 1st could read as due on the 31st.
String dateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Builds the `search_terms` array that free-text search is matched against.
///
/// Firestore has no text search and cannot `OR` across fields, so "find
/// transactions mentioning Keells" is not expressible as a query over `merchant`,
/// `description` and `notes`. The workaround is to flatten those fields into one
/// array of lowercased tokens at write time and query it with `array-contains`,
/// which is a single indexed lookup regardless of how much history there is.
///
/// Tokens in [prefixed] additionally contribute their prefixes, so typing `kee`
/// finds `Keells`. That is limited to the merchant, because every prefix is an
/// index entry and generating them for free-text notes would bloat the document
/// for little benefit. Elsewhere a whole word has to be typed — a real limitation
/// of this backend, and the honest trade against adding a search service.
List<String> searchTerms(
  Iterable<String?> values, {
  Iterable<String?> prefixed = const [],
  int maxTerms = 80,
}) {
  final terms = <String>{};

  for (final token in _tokenise(values)) {
    terms.add(token);
  }

  for (final token in _tokenise(prefixed)) {
    final limit = token.length < 12 ? token.length : 12;
    for (var length = 2; length <= limit; length++) {
      terms.add(token.substring(0, length));
    }
  }

  // Capped so one pathological note cannot push the document towards Firestore's
  // per-document index-entry ceiling.
  return terms.take(maxTerms).toList(growable: false);
}

/// Splits a user's search box input into the same tokens [searchTerms] produced.
List<String> searchQueryTerms(String input) =>
    _tokenise([input]).toList(growable: false);

Iterable<String> _tokenise(Iterable<String?> values) {
  final tokens = <String>{};
  for (final value in values) {
    if (value == null || value.isEmpty) continue;
    for (final raw in value.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) {
      // Single characters match almost everything, so they are not worth an
      // index entry.
      if (raw.length < 2) continue;
      tokens.add(raw.length <= 24 ? raw : raw.substring(0, 24));
    }
  }
  return tokens;
}
