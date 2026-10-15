import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/app_date_utils.dart';
import '../../../shared/models/analytics.dart';

/// Builds the monthly PDF report.
///
/// Uses the `pdf` package's own layout widgets rather than rendering the Flutter
/// UI, because a report is a document — it needs page breaks, repeating table
/// headers and print-appropriate typography, none of which a screenshot gives.
///
/// Only what the user selected is included. There is no hidden metadata, no
/// account numbers and no raw OCR text in the output.
class PdfReportBuilder {
  const PdfReportBuilder._();

  // Print-friendly palette: darker than the screen theme, since a light tint
  // that reads well on a display disappears on paper.
  static const _brand = PdfColor.fromInt(0xFF0A5C4C);
  static const _ink = PdfColor.fromInt(0xFF101828);
  static const _muted = PdfColor.fromInt(0xFF667085);
  static const _line = PdfColor.fromInt(0xFFD7DBE0);
  static const _income = PdfColor.fromInt(0xFF15803D);
  static const _expense = PdfColor.fromInt(0xFFB42318);

  static Future<Uint8List> build({
    required ReportData data,
    bool includeTransactions = true,
    bool includeBudgets = true,
    bool includeCategories = true,
  }) async {
    final document = pw.Document(
      title: 'Finora report — ${data.range.label}',
      author: 'Finora',
      creator: 'Finora',
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 44),
        header: (context) =>
            context.pageNumber == 1 ? pw.SizedBox() : _runningHeader(data),
        footer: _footer,
        build: (context) => [
          _titleBlock(data),
          pw.SizedBox(height: 20),
          _summaryBlock(data),
          pw.SizedBox(height: 18),
          _accountsBlock(data),
          if (includeCategories && data.topCategories.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            _categoriesBlock(data),
          ],
          if (includeBudgets && data.budgets.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            _budgetsBlock(data),
          ],
          if (data.largestExpenses.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            _largestBlock(data),
          ],
          if (includeTransactions && data.transactions.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            _transactionsBlock(data),
          ],
        ],
      ),
    );

    return document.save();
  }

  static pw.Widget _titleBlock(ReportData data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Finora',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: _brand,
                  ),
                ),
                pw.Text(
                  'Financial report',
                  style: const pw.TextStyle(fontSize: 10, color: _muted),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  data.userName,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: _ink,
                  ),
                ),
                pw.Text(
                  'Generated ${DateDisplay.dayMonthYear(data.generatedAt)}',
                  style: const pw.TextStyle(fontSize: 9, color: _muted),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Container(height: 2, color: _brand),
        pw.SizedBox(height: 14),
        pw.Text(
          data.range.label,
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
        pw.Text(
          '${data.transactionCount} transactions · ${data.currency}',
          style: const pw.TextStyle(fontSize: 10, color: _muted),
        ),
      ],
    );
  }

  static pw.Widget _runningHeader(ReportData data) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Finora · ${data.range.label}',
                style: const pw.TextStyle(fontSize: 9, color: _muted),
              ),
              pw.Text(
                data.userName,
                style: const pw.TextStyle(fontSize: 9, color: _muted),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Container(height: 0.6, color: _line),
        ],
      ),
    );
  }

  static pw.Widget _footer(pw.Context context) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated by Finora',
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          ),
        ],
      ),
    );
  }

  static pw.Widget _summaryBlock(ReportData data) {
    final summary = data.summary;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Summary'),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            _statCard('Income', summary.income.format(), _income),
            pw.SizedBox(width: 8),
            _statCard('Expenses', summary.expenses.format(), _expense),
            pw.SizedBox(width: 8),
            _statCard(
              summary.isOverspending ? 'Overspent' : 'Savings',
              summary.savings.abs.format(),
              summary.isOverspending ? _expense : _income,
            ),
            pw.SizedBox(width: 8),
            _statCard(
              'Savings rate',
              summary.income.isZero
                  ? '—'
                  : '${summary.savingsRate.toStringAsFixed(1)}%',
              _ink,
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Transfers between your own accounts are excluded from income and '
          'expenses.',
          style: const pw.TextStyle(fontSize: 8, color: _muted),
        ),
      ],
    );
  }

  static pw.Widget _statCard(String label, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _line),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label.toUpperCase(),
              style: const pw.TextStyle(fontSize: 7, color: _muted),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _accountsBlock(ReportData data) {
    final accounts = data.accounts.where((a) => !a.isArchived).toList();
    if (accounts.isEmpty) return pw.SizedBox();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Account balances'),
        pw.SizedBox(height: 6),
        _table(
          headers: const ['Account', 'Type', 'Currency', 'Balance'],
          alignments: const [
            pw.Alignment.centerLeft,
            pw.Alignment.centerLeft,
            pw.Alignment.center,
            pw.Alignment.centerRight,
          ],
          widths: const {0: 3, 1: 2, 2: 1, 3: 2},
          rows: [
            for (final account in accounts)
              [
                account.name,
                account.type.label,
                account.currency,
                account.currentBalance.format(),
              ],
          ],
        ),
      ],
    );
  }

  static pw.Widget _categoriesBlock(ReportData data) {
    final total = data.categoryBreakdown.total;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Spending by category'),
        pw.SizedBox(height: 6),
        // A table rather than a pie chart: the exact figures matter more on
        // paper, and a bar column shows the shape without needing colour.
        _table(
          headers: const ['Category', 'Transactions', 'Share', 'Amount'],
          alignments: const [
            pw.Alignment.centerLeft,
            pw.Alignment.center,
            pw.Alignment.centerLeft,
            pw.Alignment.centerRight,
          ],
          widths: const {0: 3, 1: 1.4, 2: 2, 3: 2},
          rows: [
            for (final item in data.topCategories)
              [
                item.categoryName,
                '${item.transactionCount}',
                _shareBar(item.shareOf(total)),
                item.total.format(),
              ],
          ],
        ),
      ],
    );
  }

  /// A text-only bar, so it survives black-and-white printing.
  static String _shareBar(double percent) {
    final filled = (percent / 10).round().clamp(0, 10);
    return '${'#' * filled}${'.' * (10 - filled)}  '
        '${percent.toStringAsFixed(percent >= 10 ? 0 : 1)}%';
  }

  static pw.Widget _budgetsBlock(ReportData data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Budget performance'),
        pw.SizedBox(height: 6),
        _table(
          headers: const ['Budget', 'Limit', 'Spent', 'Remaining', 'Used'],
          alignments: const [
            pw.Alignment.centerLeft,
            pw.Alignment.centerRight,
            pw.Alignment.centerRight,
            pw.Alignment.centerRight,
            pw.Alignment.centerRight,
          ],
          widths: const {0: 3, 1: 2, 2: 2, 3: 2, 4: 1.8},
          rows: [
            for (final progress in data.budgets)
              [
                progress.budget.displayName,
                progress.limit.format(),
                progress.spent.format(),
                progress.isExceeded
                    ? '-${progress.overspend.format()}'
                    : progress.remaining.format(),
                // An exceeded budget is marked in the text itself, so it
                // survives black-and-white printing where a tint would not.
                progress.isExceeded
                    ? '${progress.percentUsed.toStringAsFixed(0)}%  (over)'
                    : '${progress.percentUsed.toStringAsFixed(0)}%',
              ],
          ],
        ),
      ],
    );
  }

  static pw.Widget _largestBlock(ReportData data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Largest expenses'),
        pw.SizedBox(height: 6),
        _table(
          headers: const ['Date', 'Merchant', 'Category', 'Amount'],
          alignments: const [
            pw.Alignment.centerLeft,
            pw.Alignment.centerLeft,
            pw.Alignment.centerLeft,
            pw.Alignment.centerRight,
          ],
          widths: const {0: 1.6, 1: 3, 2: 2, 3: 2},
          rows: [
            for (final transaction in data.largestExpenses)
              [
                DateDisplay.dayMonth(transaction.transactionDate),
                transaction.title,
                transaction.category?.name ?? '—',
                transaction.amount.format(),
              ],
          ],
        ),
      ],
    );
  }

  static pw.Widget _transactionsBlock(ReportData data) {
    final sorted = [...data.transactions]
      ..sort((a, b) => a.transactionDate.compareTo(b.transactionDate));

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('All transactions'),
        pw.SizedBox(height: 6),
        _table(
          headers: const [
            'Date',
            'Type',
            'Merchant / description',
            'Category',
            'Account',
            'Amount',
          ],
          alignments: const [
            pw.Alignment.centerLeft,
            pw.Alignment.centerLeft,
            pw.Alignment.centerLeft,
            pw.Alignment.centerLeft,
            pw.Alignment.centerLeft,
            pw.Alignment.centerRight,
          ],
          widths: const {0: 1.5, 1: 1.4, 2: 3.2, 3: 1.8, 4: 1.8, 5: 1.8},
          fontSize: 7.5,
          rows: [
            for (final transaction in sorted)
              [
                DateDisplay.dayMonth(transaction.transactionDate),
                transaction.type.label,
                transaction.title,
                transaction.category?.name ?? '—',
                transaction.account?.name ?? '—',
                transaction.signedAmount.format(showSymbol: false),
              ],
          ],
        ),
      ],
    );
  }

  static pw.Widget _sectionTitle(String title) {
    return pw.Text(
      title,
      style: pw.TextStyle(
        fontSize: 12,
        fontWeight: pw.FontWeight.bold,
        color: _ink,
      ),
    );
  }

  /// A table whose header repeats on every page — essential for a transaction
  /// list that spans several pages.
  static pw.Widget _table({
    required List<String> headers,
    required List<List<String>> rows,
    required List<pw.Alignment> alignments,
    Map<int, double>? widths,
    double fontSize = 8.5,
  }) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      border: null,
      headerDecoration: const pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFF2F4F7),
      ),
      headerStyle: pw.TextStyle(
        fontSize: fontSize,
        fontWeight: pw.FontWeight.bold,
        color: _ink,
      ),
      cellStyle: pw.TextStyle(fontSize: fontSize, color: _ink),
      cellHeight: 16,
      headerHeight: 18,
      cellAlignments: {
        for (var i = 0; i < alignments.length; i++) i: alignments[i],
      },
      columnWidths: widths == null
          ? null
          : {
              for (final entry in widths.entries)
                entry.key: pw.FlexColumnWidth(entry.value),
            },
      oddRowDecoration: const pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFFAFBFC),
      ),
      rowDecoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.4)),
      ),
    );
  }
}
