import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter/material.dart';

import '../../core/constants/enums.dart';
import '../../core/services/firebase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/money.dart';
import '../models/account.dart';
import '../models/analytics.dart';
import '../models/category.dart';
import '../models/json_map.dart';
import '../models/transaction.dart';
import 'base_repository.dart';

/// Reads the aggregate figures.
///
/// Postgres could sum a year of transactions in a function and return one row.
/// Firestore has no server-side aggregation beyond `count()`, and bills per
/// document read, so the equivalent would mean downloading every transaction in
/// the period each time the dashboard opened — slow, and metered.
///
/// So the totals are maintained as they happen. The `onTransactionWritten`
/// trigger keeps one rollup document per month at
/// `users/{uid}/monthlySummaries/{YYYY-MM}`, updating it with
/// `FieldValue.increment` so concurrent writes accumulate instead of overwriting.
/// Reading a year of history then costs twelve document reads rather than several
/// thousand.
///
/// **When the rollups cannot answer the question**, this falls back to reading the
/// transactions in the range and summing them here. That happens for a range that
/// does not align to whole months, and for a per-account filter, because a rollup
/// is a whole-month, all-accounts figure. [AggregateSource] reports which path was
/// taken, and the fallback is capped so an unbounded range cannot run away with
/// the user's read quota.
class AnalyticsRepository extends BaseRepository {
  AnalyticsRepository({super.firestore});

  /// Ceiling on documents read by the fallback path.
  static const int _scanLimit = 3000;

  /// Merchant keys kept per month. Past this the trigger stops adding new ones,
  /// so a month of unique merchants cannot grow the document towards Firestore's
  /// 1 MB limit. The chart shows ten.
  static const int merchantKeyLimit = 200;

  CollectionReference<Map<String, dynamic>> get _rollups =>
      FirebaseService.monthlySummaries(userId);

  // -------------------------------------------------------------------------
  // The one aggregation everything else reads from
  // -------------------------------------------------------------------------

  /// Totals for [range], from the rollups when they can answer and from the
  /// transactions themselves when they cannot.
  Future<PeriodAggregate> aggregate({
    required DateRange range,
    required String currency,
    Set<String> accountIds = const {},
  }) =>
      guard(() async {
        if (accountIds.isEmpty && _isMonthAligned(range)) {
          return _fromRollups(range: range, currency: currency);
        }
        return _fromTransactions(
          range: range,
          currency: currency,
          accountIds: accountIds,
        );
      });

  /// True when [range] covers whole calendar months, which is what a rollup is.
  ///
  /// "September" and "this year" align. "The last 30 days" does not, and summing
  /// whole months for it would overstate both ends.
  static bool _isMonthAligned(DateRange range) {
    final start = range.start;
    final end = range.end;
    final startsOnFirst = start.day == 1 &&
        start.hour == 0 &&
        start.minute == 0;
    final lastDay = AppDateUtils.endOfMonth(end);
    final endsOnLast = end.day == lastDay.day;
    return startsOnFirst && endsOnLast;
  }

  Future<PeriodAggregate> _fromRollups({
    required DateRange range,
    required String currency,
  }) async {
    final keys = _monthKeysIn(range);
    if (keys.isEmpty) {
      return PeriodAggregate.empty(range, currency, AggregateSource.rollup);
    }

    // `whereIn` on the document id, so a year is one query rather than twelve.
    final snapshots = <Json>[];
    for (var start = 0; start < keys.length; start += 30) {
      final chunk = keys.sublist(
        start,
        start + 30 > keys.length ? keys.length : start + 30,
      );
      final snapshot =
          await _rollups.where(FieldPath.documentId, whereIn: chunk).get();
      snapshots.addAll(snapshot.docs.map((doc) => doc.asJson));
    }

    final builder = _AggregateBuilder(currency);
    for (final rollup in snapshots) {
      builder.addRollup(rollup);
    }

    return builder.build(range, AggregateSource.rollup);
  }

  Future<PeriodAggregate> _fromTransactions({
    required DateRange range,
    required String currency,
    required Set<String> accountIds,
  }) async {
    Query<Map<String, dynamic>> query = FirebaseService.transactions(userId)
        .where(
          'transaction_date',
          isGreaterThanOrEqualTo: Timestamp.fromDate(range.start),
          isLessThanOrEqualTo: Timestamp.fromDate(range.end),
        )
        .orderBy('transaction_date');

    // One `whereIn` is allowed; more accounts than that are filtered below.
    if (accountIds.isNotEmpty && accountIds.length <= 30) {
      query = accountIds.length == 1
          ? query.where('account_id', isEqualTo: accountIds.single)
          : query.where('account_id', whereIn: accountIds.toList());
    }

    final snapshot = await query.limit(_scanLimit).get();
    final builder = _AggregateBuilder(currency);

    for (final doc in snapshot.docs) {
      final json = doc.asJson;
      if (accountIds.length > 30 &&
          !accountIds.contains(json.strOrNull('account_id'))) {
        continue;
      }
      builder.addTransaction(json);
    }

    return builder.build(
      range,
      snapshot.docs.length >= _scanLimit
          ? AggregateSource.truncatedScan
          : AggregateSource.scan,
    );
  }

  static List<String> _monthKeysIn(DateRange range) {
    final keys = <String>[];
    var cursor = DateTime(range.start.year, range.start.month);
    final last = DateTime(range.end.year, range.end.month);
    while (!cursor.isAfter(last) && keys.length < 120) {
      keys.add(FirebaseService.monthKey(cursor));
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return keys;
  }

  // -------------------------------------------------------------------------
  // The shapes the UI asks for
  // -------------------------------------------------------------------------

  Future<CashflowSummary> fetchCashflow({
    required DateRange range,
    required String currency,
    Set<String> accountIds = const {},
  }) async {
    final totals = await aggregate(
      range: range,
      currency: currency,
      accountIds: accountIds,
    );
    return CashflowSummary(
      range: range,
      income: totals.income,
      expenses: totals.expenses,
    );
  }

  Future<int> fetchTransactionCount({required DateRange range}) async {
    // A count does not need the rollups at all: Firestore's aggregation query
    // returns it without reading the documents.
    return countOf(
      FirebaseService.transactions(userId).where(
        'transaction_date',
        isGreaterThanOrEqualTo: Timestamp.fromDate(range.start),
        isLessThanOrEqualTo: Timestamp.fromDate(range.end),
      ),
    );
  }

  Future<CategoryBreakdown> fetchCategoryBreakdown({
    required DateRange range,
    required String currency,
    TransactionType type = TransactionType.expense,
    Set<String> accountIds = const {},
  }) async {
    final totals = await aggregate(
      range: range,
      currency: currency,
      accountIds: accountIds,
    );
    final index = await relations.load();

    final raw = type == TransactionType.income
        ? totals.incomeByCategory
        : totals.expensesByCategory;

    final entries = raw.entries.toList()
      ..sort((a, b) => b.value.minor.compareTo(a.value.minor));

    final items = <CategoryBreakdownItem>[];
    var total = Money.zero(currency);
    var paletteIndex = 0;

    for (final entry in entries) {
      if (entry.value.minor == 0) continue;

      final categoryId = entry.key == _uncategorised ? null : entry.key;
      final category = index.category(categoryId);
      final amount = Money.fromMinorUnits(entry.value.minor, currency);
      total += amount;

      final explicit = AppColors.tryParseHex(category?.strOrNull('color'));

      items.add(CategoryBreakdownItem(
        categoryId: categoryId,
        categoryName: category?.str('name') ?? 'Uncategorised',
        total: amount,
        transactionCount: entry.value.count,
        // A category with no colour of its own gets a stable palette slot, so a
        // chart does not change colours between visits.
        color: explicit ??
            (categoryId != null
                ? AppColors.deterministic(categoryId)
                : AppColors.categoryPalette[
                    paletteIndex++ % AppColors.categoryPalette.length]),
        icon: CategoryIcons.resolve(
          category?.strOrNull('icon'),
          type == TransactionType.income
              ? CategoryKind.income
              : CategoryKind.expense,
        ),
      ));
    }

    return CategoryBreakdown(items: items, total: total, range: range);
  }

  /// Monthly or daily series, chosen from the span of [range].
  ///
  /// A week of daily points is informative; a year of them is 365 unreadable
  /// bars, so anything beyond about two months is bucketed by month. The monthly
  /// form reads one document per month; the daily form reads the per-day map the
  /// trigger keeps inside each rollup.
  Future<TimeSeries> fetchTimeSeries({
    required DateRange range,
    required String currency,
    Set<String> accountIds = const {},
    bool? daily,
  }) async {
    final useDaily = daily ?? range.dayCount <= 62;
    final totals = await aggregate(
      range: range,
      currency: currency,
      accountIds: accountIds,
    );

    final buckets = useDaily ? totals.byDay : totals.byMonth;
    final points = <TimeSeriesPoint>[];

    final keys = buckets.keys.toList()..sort();
    for (final key in keys) {
      final start = useDaily ? _parseDayKey(key) : _parseMonthKey(key);
      if (start == null) continue;
      if (start.isBefore(AppDateUtils.startOfDay(range.start)) ||
          start.isAfter(range.end)) {
        continue;
      }

      final bucket = buckets[key]!;
      points.add(TimeSeriesPoint(
        periodStart: start,
        label: useDaily
            ? DateDisplay.dayMonth(start)
            : DateDisplay.monthShort(start),
        income: Money.fromMinorUnits(bucket.incomeMinor, currency),
        expenses: Money.fromMinorUnits(bucket.expensesMinor, currency),
      ));
    }

    return TimeSeries(points: points, currency: currency);
  }

  Future<List<MerchantTotal>> fetchTopMerchants({
    required DateRange range,
    required String currency,
    int limit = 10,
  }) async {
    final totals = await aggregate(range: range, currency: currency);

    final entries = totals.byMerchant.values.toList()
      ..sort((a, b) => b.totalMinor.compareTo(a.totalMinor));

    return entries
        .take(limit)
        .map((entry) => MerchantTotal(
              merchant: entry.name,
              total: Money.fromMinorUnits(entry.totalMinor, currency),
              transactionCount: entry.count,
              lastTransactionDate: entry.lastDate,
            ))
        .toList(growable: false);
  }

  Future<List<PaymentMethodTotal>> fetchPaymentMethodTotals({
    required DateRange range,
    required String currency,
  }) async {
    final totals = await aggregate(range: range, currency: currency);

    final entries = totals.byPaymentMethod.entries.toList()
      ..sort((a, b) => b.value.minor.compareTo(a.value.minor));

    return entries
        .map((entry) => PaymentMethodTotal(
              method: entry.key == _unspecifiedMethod
                  ? null
                  : PaymentMethod.fromWire(entry.key),
              total: Money.fromMinorUnits(entry.value.minor, currency),
              transactionCount: entry.value.count,
            ))
        .toList(growable: false);
  }

  /// The single largest expense in a period, for the reports summary.
  ///
  /// The id is taken from the rollups, which the trigger keeps up to date, and
  /// the transaction is then read by id. Querying for it directly would need to
  /// order by amount inside a date range, which Firestore does not allow without
  /// the range field leading the sort.
  Future<Transaction?> fetchLargestExpense({required DateRange range}) =>
      guard(() async {
        final totals = await aggregate(range: range, currency: 'LKR');
        final id = totals.largestExpenseId;
        if (id == null) return null;

        final snapshot =
            await FirebaseService.transactions(userId).doc(id).get();
        if (!snapshot.exists) return null;

        final index = await relations.load();
        return Transaction.fromJson(index.attach(snapshot.asJson));
      });

  /// Everything the Analytics screen needs.
  ///
  /// One aggregation covers almost all of it, which is the point of the rollups:
  /// the Postgres build issued nine parallel function calls here, and this issues
  /// a handful of document reads and does the shaping in Dart.
  Future<AnalyticsData> fetchAnalytics({
    required DateRange range,
    required String currency,
    required List<Account> accounts,
    Set<String> accountIds = const {},
  }) async {
    final (current, previous, count) = await (
      aggregate(range: range, currency: currency, accountIds: accountIds),
      aggregate(
        range: range.previousPeriod,
        currency: currency,
        accountIds: accountIds,
      ),
      fetchTransactionCount(range: range),
    ).wait;

    final (expenseBreakdown, incomeBreakdown, trend, merchants, methods, largest) =
        await (
      fetchCategoryBreakdown(
        range: range,
        currency: currency,
        accountIds: accountIds,
      ),
      fetchCategoryBreakdown(
        range: range,
        currency: currency,
        type: TransactionType.income,
        accountIds: accountIds,
      ),
      fetchTimeSeries(range: range, currency: currency, accountIds: accountIds),
      fetchTopMerchants(range: range, currency: currency),
      fetchPaymentMethodTotals(range: range, currency: currency),
      fetchLargestExpense(range: range),
    ).wait;

    return AnalyticsData(
      range: range,
      currency: currency,
      summary: CashflowSummary(
        range: range,
        income: current.income,
        expenses: current.expenses,
      ),
      previousSummary: CashflowSummary(
        range: range.previousPeriod,
        income: previous.income,
        expenses: previous.expenses,
      ),
      expenseBreakdown: expenseBreakdown,
      incomeBreakdown: incomeBreakdown,
      monthlyTrend: trend,
      topMerchants: merchants,
      paymentMethods: methods,
      accountBalances: accounts,
      transactionCount: count,
      largestExpense: largest,
    );
  }

  /// Colour for a slice that has no category of its own.
  static Color otherSliceColor(bool isDark) =>
      isDark ? const Color(0xFF667085) : const Color(0xFF98A2B3);

  static DateTime? _parseMonthKey(String key) {
    final parts = key.split('-');
    if (parts.length < 2) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null) return null;
    return DateTime(year, month);
  }

  static DateTime? _parseDayKey(String key) {
    final parts = key.split('-');
    if (parts.length < 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }
}

/// Key used for transactions with no category, in the rollup maps.
///
/// A literal rather than an absent key: Firestore map keys cannot be null, and an
/// explicit bucket means "uncategorised" shows up in the breakdown instead of
/// quietly vanishing from the total.
const String _uncategorised = 'uncategorised';
const String _unspecifiedMethod = 'unspecified';

/// Where a [PeriodAggregate] came from, so a caller can say so.
enum AggregateSource {
  /// Read from the maintained monthly rollups: cheap and exact.
  rollup,

  /// Summed from the transactions in the range, because the rollups could not
  /// answer this question.
  scan,

  /// A scan that hit the read ceiling, so the figures are of the documents read
  /// rather than of the whole range.
  truncatedScan,
}

/// Totals over a period, however they were obtained.
class PeriodAggregate {
  const PeriodAggregate({
    required this.range,
    required this.currency,
    required this.source,
    required this.income,
    required this.expenses,
    required this.transactionCount,
    required this.expensesByCategory,
    required this.incomeByCategory,
    required this.byPaymentMethod,
    required this.byMerchant,
    required this.byMonth,
    required this.byDay,
    this.largestExpenseId,
  });

  PeriodAggregate.empty(this.range, this.currency, this.source)
      : income = Money.zero(currency),
        expenses = Money.zero(currency),
        transactionCount = 0,
        expensesByCategory = const {},
        incomeByCategory = const {},
        byPaymentMethod = const {},
        byMerchant = const {},
        byMonth = const {},
        byDay = const {},
        largestExpenseId = null;

  final DateRange range;
  final String currency;
  final AggregateSource source;
  final Money income;
  final Money expenses;
  final int transactionCount;
  final Map<String, CountedTotal> expensesByCategory;
  final Map<String, CountedTotal> incomeByCategory;
  final Map<String, CountedTotal> byPaymentMethod;
  final Map<String, MerchantAggregate> byMerchant;

  /// `YYYY-MM` to that month's figures.
  final Map<String, PeriodBucket> byMonth;

  /// `YYYY-MM-DD` to that day's figures.
  final Map<String, PeriodBucket> byDay;

  final String? largestExpenseId;

  /// Whether these figures cover the whole range asked for.
  bool get isComplete => source != AggregateSource.truncatedScan;
}

class CountedTotal {
  const CountedTotal(this.minor, this.count);

  final int minor;
  final int count;

  CountedTotal operator +(CountedTotal other) =>
      CountedTotal(minor + other.minor, count + other.count);
}

class PeriodBucket {
  const PeriodBucket(this.incomeMinor, this.expensesMinor);

  final int incomeMinor;
  final int expensesMinor;

  PeriodBucket operator +(PeriodBucket other) => PeriodBucket(
        incomeMinor + other.incomeMinor,
        expensesMinor + other.expensesMinor,
      );
}

class MerchantAggregate {
  const MerchantAggregate({
    required this.name,
    required this.totalMinor,
    required this.count,
    this.lastDate,
  });

  final String name;
  final int totalMinor;
  final int count;
  final DateTime? lastDate;

  MerchantAggregate operator +(MerchantAggregate other) => MerchantAggregate(
        name: name,
        totalMinor: totalMinor + other.totalMinor,
        count: count + other.count,
        lastDate: switch ((lastDate, other.lastDate)) {
          (null, final b) => b,
          (final a, null) => a,
          (final a?, final b?) => a.isAfter(b) ? a : b,
        },
      );
}

/// Accumulates either rollup documents or raw transactions into one shape.
///
/// Both paths produce the same [PeriodAggregate], so the rest of this file does
/// not need to know which was used — and a bug in one path shows up as a
/// disagreement with the other rather than as two different-looking screens.
class _AggregateBuilder {
  _AggregateBuilder(this.currency);

  final String currency;

  int _incomeMinor = 0;
  int _expensesMinor = 0;
  int _count = 0;
  String? _largestId;
  int _largestMinor = 0;

  final Map<String, CountedTotal> _expenseCategories = {};
  final Map<String, CountedTotal> _incomeCategories = {};
  final Map<String, CountedTotal> _methods = {};
  final Map<String, MerchantAggregate> _merchants = {};
  final Map<String, PeriodBucket> _months = {};
  final Map<String, PeriodBucket> _days = {};

  /// Folds in one `monthlySummaries` document.
  void addRollup(Json rollup) {
    final monthKey = rollup.str('month', fallback: rollup.str('id'));

    final income = rollup.intVal(minorKey('income'));
    final expenses = rollup.intVal(minorKey('expenses'));
    _incomeMinor += income;
    _expensesMinor += expenses;
    _count += rollup.intVal('transaction_count');

    if (monthKey.isNotEmpty) {
      _months[monthKey] =
          (_months[monthKey] ?? const PeriodBucket(0, 0)) +
              PeriodBucket(income, expenses);
    }

    rollup.jsonVal('by_day').forEach((day, value) {
      if (value is! Map) return;
      final bucket = Map<String, dynamic>.from(value);
      // Day keys are stored as `01`…`31` so they sort inside the document; the
      // month is prepended here to make them absolute.
      final key = day.length == 2 ? '$monthKey-$day' : day;
      _days[key] = (_days[key] ?? const PeriodBucket(0, 0)) +
          PeriodBucket(
            bucket.intVal(minorKey('income')),
            bucket.intVal(minorKey('expenses')),
          );
    });

    rollup.jsonVal('by_category').forEach((categoryId, value) {
      if (value is! Map) return;
      final bucket = Map<String, dynamic>.from(value);
      final expense = bucket.intVal(minorKey('expense'));
      final incomeTotal = bucket.intVal(minorKey('income'));
      final count = bucket.intVal('count');

      if (expense != 0) {
        _expenseCategories[categoryId] =
            (_expenseCategories[categoryId] ?? const CountedTotal(0, 0)) +
                CountedTotal(expense, count);
      }
      if (incomeTotal != 0) {
        _incomeCategories[categoryId] =
            (_incomeCategories[categoryId] ?? const CountedTotal(0, 0)) +
                CountedTotal(incomeTotal, count);
      }
    });

    rollup.jsonVal('by_payment_method').forEach((method, value) {
      if (value is! Map) return;
      final bucket = Map<String, dynamic>.from(value);
      _methods[method] = (_methods[method] ?? const CountedTotal(0, 0)) +
          CountedTotal(bucket.intVal(minorKey('total')), bucket.intVal('count'));
    });

    rollup.jsonVal('by_merchant').forEach((key, value) {
      if (value is! Map) return;
      final bucket = Map<String, dynamic>.from(value);
      final entry = MerchantAggregate(
        name: bucket.str('name', fallback: key),
        totalMinor: bucket.intVal(minorKey('total')),
        count: bucket.intVal('count'),
        lastDate: bucket.dateOrNull('last_date'),
      );
      _merchants[key] = _merchants.containsKey(key)
          ? _merchants[key]! + entry
          : entry;
    });

    final largest = rollup.jsonVal('largest_expense');
    final largestMinor = largest.intVal(minorKey('amount'));
    if (largestMinor > _largestMinor) {
      _largestMinor = largestMinor;
      _largestId = largest.strOrNull('transaction_id');
    }
  }

  /// Folds in one transaction document, for the fallback path.
  void addTransaction(Json row) {
    final type = TransactionType.fromWire(row.strOrNull('type'));
    final status = TransactionStatus.fromWire(row.strOrNull('status'));

    // Transfers move money between the user's own accounts, so counting them
    // would inflate both income and expenses by the same amount and make the
    // month look twice as busy as it was. Pending rows are excluded for the same
    // reason the triggers exclude them: they have not happened yet.
    if (type.isTransfer || status != TransactionStatus.confirmed) return;

    final minor = row.intVal(minorKey('amount'));
    final date = row.dateVal('transaction_date');
    final monthKey = FirebaseService.monthKey(date);
    final dayKey = dateOnly(date);
    final categoryId = row.strOrNull('category_id') ?? _uncategorised;

    _count++;

    if (type == TransactionType.income) {
      _incomeMinor += minor;
      _incomeCategories[categoryId] =
          (_incomeCategories[categoryId] ?? const CountedTotal(0, 0)) +
              CountedTotal(minor, 1);
      _months[monthKey] = (_months[monthKey] ?? const PeriodBucket(0, 0)) +
          PeriodBucket(minor, 0);
      _days[dayKey] =
          (_days[dayKey] ?? const PeriodBucket(0, 0)) + PeriodBucket(minor, 0);
      return;
    }

    _expensesMinor += minor;
    _expenseCategories[categoryId] =
        (_expenseCategories[categoryId] ?? const CountedTotal(0, 0)) +
            CountedTotal(minor, 1);
    _months[monthKey] =
        (_months[monthKey] ?? const PeriodBucket(0, 0)) + PeriodBucket(0, minor);
    _days[dayKey] =
        (_days[dayKey] ?? const PeriodBucket(0, 0)) + PeriodBucket(0, minor);

    final method = row.strOrNull('payment_method') ?? _unspecifiedMethod;
    _methods[method] =
        (_methods[method] ?? const CountedTotal(0, 0)) + CountedTotal(minor, 1);

    final merchant = row.strOrNull('merchant');
    if (merchant != null) {
      final key = merchant.toLowerCase().trim();
      final entry = MerchantAggregate(
        name: merchant,
        totalMinor: minor,
        count: 1,
        lastDate: date,
      );
      _merchants[key] =
          _merchants.containsKey(key) ? _merchants[key]! + entry : entry;
    }

    if (minor > _largestMinor) {
      _largestMinor = minor;
      _largestId = row.strOrNull('id');
    }
  }

  PeriodAggregate build(DateRange range, AggregateSource source) =>
      PeriodAggregate(
        range: range,
        currency: currency,
        source: source,
        income: Money.fromMinorUnits(_incomeMinor, currency),
        expenses: Money.fromMinorUnits(_expensesMinor, currency),
        transactionCount: _count,
        expensesByCategory: Map.unmodifiable(_expenseCategories),
        incomeByCategory: Map.unmodifiable(_incomeCategories),
        byPaymentMethod: Map.unmodifiable(_methods),
        byMerchant: Map.unmodifiable(_merchants),
        byMonth: Map.unmodifiable(_months),
        byDay: Map.unmodifiable(_days),
        largestExpenseId: _largestId,
      );
}
