import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/enums.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../shared/models/analytics.dart';
import '../../../shared/providers/analytics_providers.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/pickers.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/csv_exporter.dart';
import '../data/pdf_report_builder.dart';

/// Reports and exports.
///
/// The period is chosen first and the preview reflects it, so the user sees what
/// they are about to export rather than discovering its contents afterwards.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateRangePreset _preset = DateRangePreset.month;
  DateRange? _customRange;

  bool _includeTransactions = true;
  bool _includeBudgets = true;
  bool _includeCategories = true;

  DateRange get _range => _preset == DateRangePreset.custom && _customRange != null
      ? _customRange!
      : AppDateUtils.rangeFor(_preset);

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(reportDataProvider(_range));

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.page),
          children: [
            AppSectionCard(
              title: 'Report period',
              icon: Icons.date_range_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final preset in DateRangePreset.values)
                        ChoiceChip(
                          label: Text(preset.label),
                          selected: _preset == preset,
                          onSelected: (_) async {
                            if (preset == DateRangePreset.custom) {
                              final range = await DateTimePickers.pickRange(
                                context,
                                initial: _range,
                              );
                              if (range != null) {
                                setState(() {
                                  _preset = preset;
                                  _customRange = range;
                                });
                              }
                            } else {
                              setState(() => _preset = preset);
                            }
                          },
                        ),
                    ],
                  ),
                  AppSpacing.gapMd,
                  Text(_range.label, style: context.text.titleSmall),
                ],
              ),
            ),
            AppSpacing.gapLg,

            report.view(
              (data) => Column(
                children: [
                  _PreviewCard(data: data),
                  AppSpacing.gapLg,
                  _ContentsCard(
                    includeTransactions: _includeTransactions,
                    includeBudgets: _includeBudgets,
                    includeCategories: _includeCategories,
                    onChanged: (transactions, budgets, categories) => setState(() {
                      _includeTransactions = transactions;
                      _includeBudgets = budgets;
                      _includeCategories = categories;
                    }),
                  ),
                  AppSpacing.gapLg,
                  _ExportCard(
                    data: data,
                    includeTransactions: _includeTransactions,
                    includeBudgets: _includeBudgets,
                    includeCategories: _includeCategories,
                  ),
                ],
              ),
              loading: const CardSkeleton(height: 260),
              onRetry: () => ref.invalidate(reportDataProvider(_range)),
            ),
            AppSpacing.gapXxl,
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends ConsumerWidget {
  const _PreviewCard({required this.data});

  final ReportData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final obscure = ref.watch(hideAmountsProvider);

    if (data.isEmpty) {
      return AppCard(
        child: Column(
          children: [
            Icon(
              Icons.description_outlined,
              size: 34,
              color: context.palette.textTertiary,
            ),
            AppSpacing.gapMd,
            Text(
              'No transactions in this period',
              style: context.text.titleSmall,
            ),
            AppSpacing.gapXs,
            Text(
              'Pick a different period to export something.',
              style: context.text.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return AppSectionCard(
      title: 'What the report will contain',
      icon: Icons.preview_outlined,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: MoneyTile(
                  label: 'Income',
                  amount: data.summary.income,
                  type: TransactionType.income,
                  obscured: obscure,
                ),
              ),
              AppSpacing.hGapLg,
              Expanded(
                child: MoneyTile(
                  label: 'Expenses',
                  amount: data.summary.expenses,
                  type: TransactionType.expense,
                  obscured: obscure,
                ),
              ),
            ],
          ),
          AppSpacing.gapLg,
          const Divider(height: 1),
          AppSpacing.gapMd,
          _PreviewRow(
            label: 'Transactions',
            value: '${data.transactionCount}',
          ),
          _PreviewRow(
            label: 'Categories with spending',
            value: '${data.categoryBreakdown.items.length}',
          ),
          _PreviewRow(label: 'Budgets', value: '${data.budgets.length}'),
          _PreviewRow(
            label: 'Accounts',
            value: '${data.accounts.where((a) => !a.isArchived).length}',
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: context.text.bodyMedium)),
          Text(value, style: context.text.titleSmall),
        ],
      ),
    );
  }
}

class _ContentsCard extends StatelessWidget {
  const _ContentsCard({
    required this.includeTransactions,
    required this.includeBudgets,
    required this.includeCategories,
    required this.onChanged,
  });

  final bool includeTransactions;
  final bool includeBudgets;
  final bool includeCategories;
  final void Function(bool transactions, bool budgets, bool categories)
      onChanged;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: 'Include in the PDF',
      subtitle: 'Only what you tick is written to the file',
      icon: Icons.checklist_rounded,
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: includeCategories,
            onChanged: (value) =>
                onChanged(includeTransactions, includeBudgets, value),
            title: Text(
              'Category breakdown',
              style: context.text.titleSmall,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: includeBudgets,
            onChanged: (value) =>
                onChanged(includeTransactions, value, includeCategories),
            title: Text(
              'Budget performance',
              style: context.text.titleSmall,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: includeTransactions,
            onChanged: (value) =>
                onChanged(value, includeBudgets, includeCategories),
            title: Text(
              'Full transaction list',
              style: context.text.titleSmall,
            ),
            subtitle: Text(
              'Makes the file longer but complete',
              style: context.text.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportCard extends ConsumerStatefulWidget {
  const _ExportCard({
    required this.data,
    required this.includeTransactions,
    required this.includeBudgets,
    required this.includeCategories,
  });

  final ReportData data;
  final bool includeTransactions;
  final bool includeBudgets;
  final bool includeCategories;

  @override
  ConsumerState<_ExportCard> createState() => _ExportCardState();
}

class _ExportCardState extends ConsumerState<_ExportCard> {
  bool _isBusy = false;

  Future<void> _exportCsv() async {
    if (widget.data.isEmpty) {
      AppFeedback.showValidation(context, 'There is nothing to export.');
      return;
    }

    setState(() => _isBusy = true);
    try {
      final csv = CsvExporter.build(widget.data.transactions);
      final bytes = CsvExporter.toBytes(csv);
      await _shareFile(
        bytes: bytes,
        fileName: CsvExporter.fileNameFor(widget.data.range),
        mimeType: 'text/csv',
        subject: 'Finora transactions — ${widget.data.range.label}',
      );
    } on Object catch (error) {
      if (mounted) AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _exportPdf() async {
    if (widget.data.isEmpty) {
      AppFeedback.showValidation(context, 'There is nothing to export.');
      return;
    }

    setState(() => _isBusy = true);
    try {
      // Built on this isolate rather than via `compute`: the report model holds
      // a deep graph of domain objects, and the layout cost for a realistic
      // period is small enough that the progress state covers it.
      final bytes = await PdfReportBuilder.build(
        data: widget.data,
        includeTransactions: widget.includeTransactions,
        includeBudgets: widget.includeBudgets,
        includeCategories: widget.includeCategories,
      );

      await _shareFile(
        bytes: bytes,
        fileName: 'finora-report-'
            '${DateDisplay.iso(widget.data.range.start)}.pdf',
        mimeType: 'application/pdf',
        subject: 'Finora report — ${widget.data.range.label}',
      );
    } on Object catch (error) {
      if (mounted) AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  /// Writes to a temporary file and hands it to the platform share sheet.
  ///
  /// A temporary directory, not a permanent one: the export is the user's to
  /// keep wherever they choose, and leaving copies in app storage would quietly
  /// accumulate their financial data on the device.
  Future<void> _shareFile({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String subject,
  }) async {
    if (kIsWeb) {
      // On web there is no temp directory; share the bytes directly.
      await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: mimeType, name: fileName)],
        subject: subject,
      );
      return;
    }

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);

    if (!mounted) return;

    await Share.shareXFiles(
      [XFile(file.path, mimeType: mimeType)],
      subject: subject,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: 'Export',
      icon: Icons.download_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: _isBusy ? null : _exportPdf,
            icon: _isBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.picture_as_pdf_outlined, size: 20),
            label: Text(_isBusy ? 'Preparing…' : 'PDF report'),
          ),
          AppSpacing.gapSm,
          OutlinedButton.icon(
            onPressed: _isBusy ? null : _exportCsv,
            icon: const Icon(Icons.table_chart_outlined, size: 20),
            label: const Text('CSV spreadsheet'),
          ),
          AppSpacing.gapMd,
          Text(
            'Exports contain only the data in the period you chose. Nothing is '
            'uploaded anywhere — the file goes straight to you.',
            style: context.text.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
