import 'package:intl/intl.dart';

import '../constants/enums.dart';

/// An inclusive date range used by analytics, reports and filters.
class DateRange {
  const DateRange(this.start, this.end);

  /// Start of day.
  final DateTime start;

  /// End of day (23:59:59.999).
  final DateTime end;

  bool contains(DateTime date) =>
      !date.isBefore(start) && !date.isAfter(end);

  int get dayCount => end.difference(start).inDays + 1;

  DateRange normalised() => DateRange(
        AppDateUtils.startOfDay(start),
        AppDateUtils.endOfDay(end),
      );

  /// The equivalent range immediately before this one, for period-over-period
  /// comparisons on the dashboard.
  DateRange get previousPeriod {
    final days = dayCount;
    final newEnd = AppDateUtils.endOfDay(
      start.subtract(const Duration(days: 1)),
    );
    final newStart = AppDateUtils.startOfDay(
      newEnd.subtract(Duration(days: days - 1)),
    );
    return DateRange(newStart, newEnd);
  }

  String get label {
    final sameYear = start.year == end.year;
    final sameMonth = sameYear && start.month == end.month;
    if (sameMonth && start.day == 1 && end.day == AppDateUtils.daysInMonth(end)) {
      return DateFormat('MMMM yyyy').format(start);
    }
    if (sameYear) {
      return '${DateFormat('d MMM').format(start)} – '
          '${DateFormat('d MMM yyyy').format(end)}';
    }
    return '${DateFormat('d MMM yyyy').format(start)} – '
        '${DateFormat('d MMM yyyy').format(end)}';
  }

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'DateRange($start → $end)';
}

class AppDateUtils {
  const AppDateUtils._();

  static DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  /// Weeks start on Monday.
  static DateTime startOfWeek(DateTime d) =>
      startOfDay(d.subtract(Duration(days: d.weekday - DateTime.monday)));

  static DateTime endOfWeek(DateTime d) =>
      endOfDay(startOfWeek(d).add(const Duration(days: 6)));

  static DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month);

  static DateTime endOfMonth(DateTime d) =>
      DateTime(d.year, d.month, daysInMonth(d), 23, 59, 59, 999);

  static DateTime startOfYear(DateTime d) => DateTime(d.year);

  static DateTime endOfYear(DateTime d) =>
      DateTime(d.year, 12, 31, 23, 59, 59, 999);

  static int daysInMonth(DateTime d) => DateTime(d.year, d.month + 1, 0).day;

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool isToday(DateTime d) => isSameDay(d, DateTime.now());

  static bool isYesterday(DateTime d) =>
      isSameDay(d, DateTime.now().subtract(const Duration(days: 1)));

  static bool isTomorrow(DateTime d) =>
      isSameDay(d, DateTime.now().add(const Duration(days: 1)));

  static DateRange thisMonth([DateTime? now]) {
    final d = now ?? DateTime.now();
    return DateRange(startOfMonth(d), endOfMonth(d));
  }

  static DateRange rangeFor(DateRangePreset preset, {DateTime? now}) {
    final d = now ?? DateTime.now();
    switch (preset) {
      case DateRangePreset.week:
        return DateRange(startOfWeek(d), endOfWeek(d));
      case DateRangePreset.month:
        return DateRange(startOfMonth(d), endOfMonth(d));
      case DateRangePreset.threeMonths:
        return DateRange(
          startOfMonth(DateTime(d.year, d.month - 2)),
          endOfMonth(d),
        );
      case DateRangePreset.sixMonths:
        return DateRange(
          startOfMonth(DateTime(d.year, d.month - 5)),
          endOfMonth(d),
        );
      case DateRangePreset.year:
        return DateRange(startOfYear(d), endOfYear(d));
      case DateRangePreset.custom:
        return DateRange(startOfMonth(d), endOfMonth(d));
    }
  }

  /// Adds one recurrence step to [from].
  ///
  /// Month and year steps clamp the day so that a 31st-of-the-month schedule
  /// lands on the 28th/30th in shorter months instead of rolling into the next
  /// month.
  static DateTime advance(
    DateTime from,
    RecurrenceFrequency frequency, {
    int customDays = 1,
  }) {
    switch (frequency) {
      case RecurrenceFrequency.daily:
        return from.add(const Duration(days: 1));
      case RecurrenceFrequency.weekly:
        return from.add(const Duration(days: 7));
      case RecurrenceFrequency.biweekly:
        return from.add(const Duration(days: 14));
      case RecurrenceFrequency.monthly:
        return _addMonthsClamped(from, 1);
      case RecurrenceFrequency.quarterly:
        return _addMonthsClamped(from, 3);
      case RecurrenceFrequency.yearly:
        return _addMonthsClamped(from, 12);
      case RecurrenceFrequency.custom:
        return from.add(Duration(days: customDays < 1 ? 1 : customDays));
    }
  }

  static DateTime _addMonthsClamped(DateTime from, int months) {
    final targetMonthFirst = DateTime(from.year, from.month + months);
    final maxDay = daysInMonth(targetMonthFirst);
    return DateTime(
      targetMonthFirst.year,
      targetMonthFirst.month,
      from.day > maxDay ? maxDay : from.day,
      from.hour,
      from.minute,
    );
  }

  /// Rolls [next] forward until it is in the future, so a schedule that was
  /// missed while the app was closed does not fire repeatedly for the past.
  static DateTime nextOccurrenceAfter(
    DateTime next,
    RecurrenceFrequency frequency, {
    DateTime? now,
    int customDays = 1,
  }) {
    final reference = now ?? DateTime.now();
    var candidate = next;
    var guard = 0;
    while (candidate.isBefore(reference) && guard < 500) {
      candidate = advance(candidate, frequency, customDays: customDays);
      guard++;
    }
    return candidate;
  }

  /// Number of months a recurrence covers per year, used to normalise
  /// subscription costs to a monthly figure.
  static double occurrencesPerMonth(
    RecurrenceFrequency frequency, {
    int customDays = 30,
  }) {
    switch (frequency) {
      case RecurrenceFrequency.daily:
        return 30.4375;
      case RecurrenceFrequency.weekly:
        return 4.348;
      case RecurrenceFrequency.biweekly:
        return 2.174;
      case RecurrenceFrequency.monthly:
        return 1;
      case RecurrenceFrequency.quarterly:
        return 1 / 3;
      case RecurrenceFrequency.yearly:
        return 1 / 12;
      case RecurrenceFrequency.custom:
        return customDays <= 0 ? 1 : 30.4375 / customDays;
    }
  }
}

/// Display formatting for dates. Kept separate from parsing (which lives in
/// the OCR parser) so screens always render dates the same way.
class DateDisplay {
  const DateDisplay._();

  static final DateFormat _dayMonth = DateFormat('d MMM');
  static final DateFormat _dayMonthYear = DateFormat('d MMM yyyy');
  static final DateFormat _weekdayFull = DateFormat('EEEE, d MMMM yyyy');
  static final DateFormat _time = DateFormat('h:mm a');
  static final DateFormat _monthYear = DateFormat('MMMM yyyy');
  static final DateFormat _monthShort = DateFormat('MMM');
  static final DateFormat _iso = DateFormat('yyyy-MM-dd');

  /// `TODAY`, `YESTERDAY`, or `MON, 15 SEP` — for list section headers.
  static String sectionHeader(DateTime date) {
    if (AppDateUtils.isToday(date)) return 'TODAY';
    if (AppDateUtils.isYesterday(date)) return 'YESTERDAY';
    final now = DateTime.now();
    if (date.year == now.year) {
      return DateFormat('EEE, d MMM').format(date).toUpperCase();
    }
    return DateFormat('EEE, d MMM yyyy').format(date).toUpperCase();
  }

  /// `Today`, `Yesterday`, `15 Sep` or `15 Sep 2025`.
  static String relative(DateTime date) {
    if (AppDateUtils.isToday(date)) return 'Today';
    if (AppDateUtils.isYesterday(date)) return 'Yesterday';
    if (AppDateUtils.isTomorrow(date)) return 'Tomorrow';
    final now = DateTime.now();
    return date.year == now.year ? _dayMonth.format(date) : _dayMonthYear.format(date);
  }

  /// A due-date description for bills: `Due today`, `Overdue by 3 days`.
  static String dueDescription(DateTime due) {
    final today = AppDateUtils.startOfDay(DateTime.now());
    final target = AppDateUtils.startOfDay(due);
    final days = target.difference(today).inDays;
    if (days == 0) return 'Due today';
    if (days == 1) return 'Due tomorrow';
    if (days == -1) return 'Overdue by 1 day';
    if (days < -1) return 'Overdue by ${-days} days';
    if (days <= 7) return 'Due in $days days';
    return 'Due ${_dayMonth.format(due)}';
  }

  static String dayMonth(DateTime d) => _dayMonth.format(d);
  static String dayMonthYear(DateTime d) => _dayMonthYear.format(d);
  static String weekdayFull(DateTime d) => _weekdayFull.format(d);
  static String time(DateTime d) => _time.format(d);
  static String monthYear(DateTime d) => _monthYear.format(d);
  static String monthShort(DateTime d) => _monthShort.format(d);
  static String iso(DateTime d) => _iso.format(d);

  static String dateTime(DateTime d) => '${relative(d)} · ${_time.format(d)}';

  /// `2 minutes ago`, `3 hours ago`, `15 Sep`.
  static String timeAgo(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    }
    return relative(d);
  }

  /// Greeting used on the dashboard header.
  static String greeting([DateTime? now]) {
    final hour = (now ?? DateTime.now()).hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}
