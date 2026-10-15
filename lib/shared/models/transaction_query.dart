import 'package:equatable/equatable.dart';

import '../../core/constants/enums.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/money.dart';

/// The full set of search, filter and sort options for the transaction list.
///
/// Immutable so it can be a Riverpod provider argument: changing any facet
/// produces a new value, which invalidates the paged query and refetches.
class TransactionQuery extends Equatable {
  const TransactionQuery({
    this.search,
    this.types = const {},
    this.categoryIds = const {},
    this.accountIds = const {},
    this.paymentMethods = const {},
    this.sources = const {},
    this.statuses = const {},
    this.dateRange,
    this.minAmount,
    this.maxAmount,
    this.sort = TransactionSort.newest,
    this.includeTransfers = true,
    this.onlyWithAttachments = false,
  });

  /// Free text matched against merchant, description and notes.
  final String? search;

  final Set<TransactionType> types;
  final Set<String> categoryIds;
  final Set<String> accountIds;
  final Set<PaymentMethod> paymentMethods;
  final Set<TransactionSource> sources;
  final Set<TransactionStatus> statuses;
  final DateRange? dateRange;
  final Money? minAmount;
  final Money? maxAmount;
  final TransactionSort sort;

  /// When false, transfer rows are hidden — useful when reviewing spending.
  final bool includeTransfers;
  final bool onlyWithAttachments;

  bool get hasSearch => search != null && search!.trim().isNotEmpty;

  /// Number of active filters, shown as a badge on the filter button.
  int get activeFilterCount {
    var count = 0;
    if (types.isNotEmpty) count++;
    if (categoryIds.isNotEmpty) count++;
    if (accountIds.isNotEmpty) count++;
    if (paymentMethods.isNotEmpty) count++;
    if (sources.isNotEmpty) count++;
    if (statuses.isNotEmpty) count++;
    if (dateRange != null) count++;
    if (minAmount != null || maxAmount != null) count++;
    if (!includeTransfers) count++;
    if (onlyWithAttachments) count++;
    return count;
  }

  bool get isEmpty => activeFilterCount == 0 && !hasSearch;

  /// A short human summary, e.g. `Expense · Food · September · > Rs. 1,000`.
  List<String> get chipLabels {
    final labels = <String>[];
    for (final t in types) {
      labels.add(t.label);
    }
    if (dateRange != null) labels.add(dateRange!.label);
    if (minAmount != null && maxAmount != null) {
      labels.add('${minAmount!.format()} – ${maxAmount!.format()}');
    } else if (minAmount != null) {
      labels.add('> ${minAmount!.format()}');
    } else if (maxAmount != null) {
      labels.add('< ${maxAmount!.format()}');
    }
    for (final m in paymentMethods) {
      labels.add(m.label);
    }
    for (final s in sources) {
      labels.add(s.label);
    }
    for (final s in statuses) {
      labels.add(s.label);
    }
    if (!includeTransfers) labels.add('No transfers');
    if (onlyWithAttachments) labels.add('With receipt');
    return labels;
  }

  TransactionQuery copyWith({
    Object? search = _sentinel,
    Set<TransactionType>? types,
    Set<String>? categoryIds,
    Set<String>? accountIds,
    Set<PaymentMethod>? paymentMethods,
    Set<TransactionSource>? sources,
    Set<TransactionStatus>? statuses,
    Object? dateRange = _sentinel,
    Object? minAmount = _sentinel,
    Object? maxAmount = _sentinel,
    TransactionSort? sort,
    bool? includeTransfers,
    bool? onlyWithAttachments,
  }) =>
      TransactionQuery(
        search: search == _sentinel ? this.search : search as String?,
        types: types ?? this.types,
        categoryIds: categoryIds ?? this.categoryIds,
        accountIds: accountIds ?? this.accountIds,
        paymentMethods: paymentMethods ?? this.paymentMethods,
        sources: sources ?? this.sources,
        statuses: statuses ?? this.statuses,
        dateRange:
            dateRange == _sentinel ? this.dateRange : dateRange as DateRange?,
        minAmount: minAmount == _sentinel ? this.minAmount : minAmount as Money?,
        maxAmount: maxAmount == _sentinel ? this.maxAmount : maxAmount as Money?,
        sort: sort ?? this.sort,
        includeTransfers: includeTransfers ?? this.includeTransfers,
        onlyWithAttachments: onlyWithAttachments ?? this.onlyWithAttachments,
      );

  /// Clears every filter but keeps the sort order and the search text.
  TransactionQuery clearFilters() => TransactionQuery(
        search: search,
        sort: sort,
      );

  static const Object _sentinel = Object();

  @override
  List<Object?> get props => [
        search,
        types,
        categoryIds,
        accountIds,
        paymentMethods,
        sources,
        statuses,
        dateRange,
        minAmount,
        maxAmount,
        sort,
        includeTransfers,
        onlyWithAttachments,
      ];
}

/// One page of results plus the state needed to fetch the next.
class Paged<T> extends Equatable {
  const Paged({
    required this.items,
    this.cursor,
    this.hasMore = false,
    this.isLoadingMore = false,
  });

  const Paged.empty()
      : items = const [],
        cursor = null,
        hasMore = true,
        isLoadingMore = false;

  final List<T> items;

  /// Where the next page starts, as the data layer chooses to express it.
  ///
  /// Deliberately untyped: this is a cursor, not a page number, because the
  /// backend pages by position rather than by offset. Keeping it as [Object] means
  /// the model layer does not have to import a Firestore snapshot type to describe
  /// "carry on from here".
  final Object? cursor;

  final bool hasMore;
  final bool isLoadingMore;

  bool get isEmpty => items.isEmpty;

  Paged<T> copyWith({
    List<T>? items,
    Object? cursor,
    bool? hasMore,
    bool? isLoadingMore,
  }) =>
      Paged<T>(
        items: items ?? this.items,
        cursor: cursor ?? this.cursor,
        hasMore: hasMore ?? this.hasMore,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      );

  @override
  List<Object?> get props => [items, cursor, hasMore, isLoadingMore];
}
