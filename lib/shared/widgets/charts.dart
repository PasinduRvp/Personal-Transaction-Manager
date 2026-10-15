import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/extensions/context_extensions.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/money.dart';
import '../models/analytics.dart';
import 'money_text.dart';

/// Charts for the dashboard, analytics and reports.
///
/// Shared conventions, applied to all of them:
///
///   * Category colour comes from the category itself, so the same category is
///     the same colour on every chart and across sessions.
///   * Income is always the palette's income colour and expenses the expense
///     colour — a reader should never have to consult a legend to tell which
///     series is which.
///   * Axis labels use compact money (`Rs. 8.5K`), because a full figure on
///     every gridline is unreadable at phone width.
///   * Every chart has an explicit empty state rather than rendering an empty
///     axis, which looks like a bug.

/// Spending by category, as a donut with the total in the middle.
class CategoryDonutChart extends StatefulWidget {
  const CategoryDonutChart({
    super.key,
    required this.items,
    required this.total,
    this.onSliceTap,
    this.centerLabel = 'Total spent',
    this.height = 200,
  });

  final List<CategoryBreakdownItem> items;
  final Money total;
  final void Function(CategoryBreakdownItem item)? onSliceTap;
  final String centerLabel;
  final double height;

  @override
  State<CategoryDonutChart> createState() => _CategoryDonutChartState();
}

class _CategoryDonutChartState extends State<CategoryDonutChart> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return _ChartEmpty(
        height: widget.height,
        icon: Icons.donut_large_outlined,
        message: 'No spending in this period',
      );
    }

    final touched = _touchedIndex >= 0 && _touchedIndex < widget.items.length
        ? widget.items[_touchedIndex]
        : null;

    return SizedBox(
      height: widget.height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: widget.height * 0.28,
              startDegreeOffset: -90,
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  final index = response?.touchedSection?.touchedSectionIndex;
                  setState(() => _touchedIndex = index ?? -1);

                  // Only a deliberate tap drills down; a hover or a drag over
                  // the chart just highlights.
                  if (event is FlTapUpEvent &&
                      index != null &&
                      index >= 0 &&
                      index < widget.items.length) {
                    widget.onSliceTap?.call(widget.items[index]);
                  }
                },
              ),
              sections: [
                for (var i = 0; i < widget.items.length; i++)
                  PieChartSectionData(
                    value: widget.items[i].total.amount.abs(),
                    color: widget.items[i].color,
                    radius: _touchedIndex == i ? 34 : 28,
                    showTitle: false,
                  ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                touched?.categoryName ?? widget.centerLabel,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelMedium,
              ),
              const SizedBox(height: 2),
              MoneyText(
                touched?.total ?? widget.total,
                size: MoneySize.large,
                compact: (touched?.total ?? widget.total).amount.abs() >= 100000,
              ),
              if (touched != null)
                Text(
                  '${touched.shareOf(widget.total).toStringAsFixed(0)}% · '
                  '${touched.transactionCount} '
                  '${touched.transactionCount == 1 ? 'item' : 'items'}',
                  style: context.text.labelSmall
                      ?.copyWith(letterSpacing: 0),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A legend to accompany the donut.
class CategoryLegend extends StatelessWidget {
  const CategoryLegend({
    super.key,
    required this.items,
    required this.total,
    this.onTap,
    this.maxItems = 6,
  });

  final List<CategoryBreakdownItem> items;
  final Money total;
  final void Function(CategoryBreakdownItem item)? onTap;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    final visible = items.take(maxItems).toList();

    return Column(
      children: [
        for (final item in visible)
          InkWell(
            onTap: onTap == null ? null : () => onTap!(item),
            borderRadius: AppRadius.smAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: item.color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  AppSpacing.hGapMd,
                  Expanded(
                    child: Text(
                      item.categoryName,
                      style: context.text.bodyMedium
                          ?.copyWith(color: context.colors.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${item.shareOf(total).toStringAsFixed(0)}%',
                    style: AppTypography.numericSmall(
                      context.palette.textTertiary,
                    ),
                  ),
                  AppSpacing.hGapMd,
                  MoneyText(item.total, size: MoneySize.row),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Income against expenses, as grouped bars.
class IncomeExpenseBarChart extends StatelessWidget {
  const IncomeExpenseBarChart({
    super.key,
    required this.series,
    this.height = 220,
    this.onBarTap,
    this.showIncome = true,
  });

  final TimeSeries series;
  final double height;
  final void Function(TimeSeriesPoint point)? onBarTap;
  final bool showIncome;

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) {
      return _ChartEmpty(
        height: height,
        icon: Icons.bar_chart_rounded,
        message: 'Not enough data yet',
      );
    }

    final maxValue = series.maxValue.amount;
    // A little headroom so the tallest bar does not touch the top gridline.
    final maxY = maxValue <= 0 ? 100.0 : maxValue * 1.18;
    final interval = _niceInterval(maxY);

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          minY: 0,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => context.isDark
                  ? context.palette.surfaceAlt
                  : const Color(0xFF1D2939),
              tooltipRoundedRadius: AppRadius.sm,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final point = series.points[group.x];
                final isIncome = showIncome && rodIndex == 0;
                final money = isIncome ? point.income : point.expenses;
                return BarTooltipItem(
                  '${point.label}\n',
                  context.text.labelSmall!
                      .copyWith(color: Colors.white70, letterSpacing: 0),
                  children: [
                    TextSpan(
                      text: '${isIncome ? 'Income' : 'Spent'} '
                          '${money.format()}',
                      style: context.text.titleSmall
                          ?.copyWith(color: Colors.white),
                    ),
                  ],
                );
              },
            ),
            touchCallback: (event, response) {
              if (event is FlTapUpEvent && response?.spot != null) {
                final index = response!.spot!.touchedBarGroupIndex;
                if (index >= 0 && index < series.points.length) {
                  onBarTap?.call(series.points[index]);
                }
              }
            },
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (_) => FlLine(
              color: context.colors.outlineVariant,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 46,
                interval: interval,
                getTitlesWidget: (value, meta) {
                  if (value == 0 || value > maxY - interval * 0.5) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    Money.fromMajor(value, series.currency)
                        .formatCompact(showSymbol: false),
                    style: AppTypography.numericSmall(
                      context.palette.textTertiary,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= series.points.length) {
                    return const SizedBox.shrink();
                  }
                  // Thin the labels when there are more points than fit.
                  final step = (series.points.length / 7).ceil();
                  if (step > 1 && index % step != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      series.points[index].label,
                      style: AppTypography.numericSmall(
                        context.palette.textTertiary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < series.points.length; i++)
              BarChartGroupData(
                x: i,
                barsSpace: 3,
                barRods: [
                  if (showIncome)
                    BarChartRodData(
                      toY: series.points[i].income.amount,
                      color: context.palette.income,
                      width: showIncome ? 7 : 12,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(3),
                      ),
                    ),
                  BarChartRodData(
                    toY: series.points[i].expenses.amount,
                    color: context.palette.expense,
                    width: showIncome ? 7 : 12,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// A cumulative line, for the savings trend and cash flow.
class TrendLineChart extends StatelessWidget {
  const TrendLineChart({
    super.key,
    required this.series,
    this.height = 200,
    this.cumulative = true,
  });

  final TimeSeries series;
  final double height;

  /// When true, plots the running total rather than each period's net.
  final bool cumulative;

  @override
  Widget build(BuildContext context) {
    if (series.points.length < 2) {
      return _ChartEmpty(
        height: height,
        icon: Icons.show_chart_rounded,
        message: 'Not enough history yet',
      );
    }

    final values = cumulative
        ? series.cumulativeNet
        : series.points.map((p) => p.net).toList();

    final amounts = values.map((v) => v.amount).toList();
    final minY = amounts.reduce((a, b) => a < b ? a : b);
    final maxY = amounts.reduce((a, b) => a > b ? a : b);
    final span = (maxY - minY).abs();
    final padding = span == 0 ? (maxY.abs() * 0.2 + 100) : span * 0.15;

    // Crossing zero matters in a savings chart, so the axis always includes it.
    final chartMin = minY > 0 ? 0.0 : minY - padding;
    final chartMax = maxY < 0 ? 0.0 : maxY + padding;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: chartMin,
          maxY: chartMax,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => context.isDark
                  ? context.palette.surfaceAlt
                  : const Color(0xFF1D2939),
              tooltipRoundedRadius: AppRadius.sm,
              getTooltipItems: (spots) => spots.map((spot) {
                final point = series.points[spot.x.toInt()];
                return LineTooltipItem(
                  '${point.label}\n',
                  context.text.labelSmall!
                      .copyWith(color: Colors.white70, letterSpacing: 0),
                  children: [
                    TextSpan(
                      text: Money.fromMajor(spot.y, series.currency).format(),
                      style: context.text.titleSmall
                          ?.copyWith(color: Colors.white),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: context.colors.outlineVariant,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 46,
                getTitlesWidget: (value, meta) => Text(
                  Money.fromMajor(value, series.currency)
                      .formatCompact(showSymbol: false),
                  style:
                      AppTypography.numericSmall(context.palette.textTertiary),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= series.points.length) {
                    return const SizedBox.shrink();
                  }
                  final step = (series.points.length / 6).ceil();
                  if (step > 1 && index % step != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      series.points[index].label,
                      style: AppTypography.numericSmall(
                        context.palette.textTertiary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < amounts.length; i++)
                  FlSpot(i.toDouble(), amounts[i]),
              ],
              isCurved: true,
              curveSmoothness: 0.28,
              barWidth: 2.5,
              color: context.colors.primary,
              dotData: FlDotData(
                show: series.points.length <= 12,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                  radius: 3,
                  color: context.colors.surface,
                  strokeWidth: 2,
                  strokeColor: context.colors.primary,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    context.colors.primary.withValues(alpha: 0.22),
                    context.colors.primary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A horizontal bar list, used for top merchants and payment methods where the
/// labels are text and a vertical axis would truncate them.
class HorizontalBarList extends StatelessWidget {
  const HorizontalBarList({
    super.key,
    required this.entries,
    this.onTap,
    this.maxItems = 8,
  });

  final List<({String label, Money amount, Color color, String? meta})> entries;
  final void Function(int index)? onTap;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const _ChartEmpty(
        height: 120,
        icon: Icons.storefront_outlined,
        message: 'No data for this period',
      );
    }

    final visible = entries.take(maxItems).toList();
    final largest = visible
        .map((e) => e.amount.minorUnits.abs())
        .reduce((a, b) => a > b ? a : b);

    return Column(
      children: [
        for (var i = 0; i < visible.length; i++)
          InkWell(
            onTap: onTap == null ? null : () => onTap!(i),
            borderRadius: AppRadius.smAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          visible[i].label,
                          style: context.text.bodyMedium
                              ?.copyWith(color: context.colors.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      AppSpacing.hGapMd,
                      MoneyText(visible[i].amount, size: MoneySize.row),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ProgressMeter(
                    fraction: largest == 0
                        ? 0
                        : visible[i].amount.minorUnits.abs() / largest,
                    color: visible[i].color,
                    height: 6,
                  ),
                  if (visible[i].meta != null) ...[
                    const SizedBox(height: 3),
                    Text(visible[i].meta!, style: context.text.labelSmall
                        ?.copyWith(letterSpacing: 0)),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A tiny inline chart for a summary card.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.height = 32,
  });

  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return SizedBox(height: height);

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          lineTouchData: const LineTouchData(enabled: false),
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < values.length; i++)
                  FlSpot(i.toDouble(), values[i]),
              ],
              isCurved: true,
              curveSmoothness: 0.3,
              barWidth: 2,
              color: color,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: color.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A legend entry for the income/expense bar chart.
class ChartLegendRow extends StatelessWidget {
  const ChartLegendRow({super.key, required this.entries});

  final List<({String label, Color color})> entries;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.sm,
      children: [
        for (final entry in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: entry.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              AppSpacing.hGapSm,
              Text(entry.label, style: context.text.labelMedium),
            ],
          ),
      ],
    );
  }
}

class _ChartEmpty extends StatelessWidget {
  const _ChartEmpty({
    required this.height,
    required this.icon,
    required this.message,
  });

  final double height;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26, color: context.palette.textTertiary),
            AppSpacing.gapMd,
            Text(message, style: context.text.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Rounds an axis interval to something a human would choose.
double _niceInterval(double maxY) {
  if (maxY <= 0) return 1;
  final rough = maxY / 4;
  final magnitude = _pow10((rough.abs()).floor().toString().length - 1);
  for (final multiplier in [1, 2, 2.5, 5, 10]) {
    final candidate = magnitude * multiplier;
    if (candidate >= rough) return candidate;
  }
  return magnitude * 10;
}

double _pow10(int exponent) {
  var result = 1.0;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}
