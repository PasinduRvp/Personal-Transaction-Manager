import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../shared/models/ocr_job.dart';
import '../../../shared/providers/ocr_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/state_views.dart';
import '../../ocr/presentation/import_source_sheet.dart';

/// Every document Finora has read, and what came of it.
///
/// This is the audit trail: a failed job stays visible with its reason, and a
/// re-read creates a new entry rather than overwriting the old one, so the
/// history stays truthful about what happened.
class ImportHistoryScreen extends ConsumerWidget {
  const ImportHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(importHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import history'),
        actions: [
          IconButton(
            onPressed: () => ImportSourceSheet.show(context),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Import document',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(importHistoryProvider),
        child: jobs.view(
          (data) => data.isEmpty
              ? EmptyState(
                  icon: Icons.document_scanner_outlined,
                  title: 'No imports yet',
                  message: 'Photograph a receipt or upload a statement and '
                      'Finora will read it for you.',
                  actionLabel: 'Import document',
                  onAction: () => ImportSourceSheet.show(context),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.page),
                  itemCount: data.length,
                  separatorBuilder: (_, __) => AppSpacing.gapMd,
                  itemBuilder: (context, index) =>
                      _JobCard(job: data[index]),
                ),
          loading: const _HistorySkeleton(),
          onRetry: () => ref.invalidate(importHistoryProvider),
        ),
      ),
    );
  }
}

class _JobCard extends ConsumerWidget {
  const _JobCard({required this.job});

  final OcrJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = job.document;
    final pending = job.candidateCount - job.confirmedCount;

    final (statusLabel, statusColor, statusIcon) = _statusFor(context, job);

    return AppCard(
      onTap: job.status.isSuccessful && job.candidateCount > 0
          ? () => context.push(AppRoutes.ocrReviewJob(job.id))
          : (document == null
              ? null
              : () => context.push(AppRoutes.documentDetail(document.id))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: document?.icon ?? Icons.description_outlined,
                color: statusColor,
                size: 42,
              ),
              AppSpacing.hGapLg,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document?.fileName ?? 'Document',
                      style: context.text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        DateDisplay.relative(job.createdAt),
                        if (document != null) document.documentType.label,
                        if (job.pageCount != null && job.pageCount! > 1)
                          '${job.pageCount} pages',
                      ].join(' · '),
                      style: context.text.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              AppChipLabel(
                label: statusLabel,
                color: statusColor,
                icon: statusIcon,
                dense: true,
              ),
            ],
          ),

          if (job.status.isSuccessful) ...[
            AppSpacing.gapLg,
            const Divider(height: 1),
            AppSpacing.gapMd,
            Row(
              children: [
                Expanded(
                  child: Text(
                    job.candidateCount == 0
                        ? 'No transactions found'
                        : '${job.candidateCount} '
                            'transaction${job.candidateCount == 1 ? '' : 's'} '
                            'detected · ${job.confirmedCount} confirmed',
                    style: context.text.bodySmall,
                  ),
                ),
                if (pending > 0)
                  AppChipLabel(
                    label: '$pending to review',
                    color: context.colors.primary,
                    dense: true,
                  ),
              ],
            ),
          ],

          if (job.isFailed) ...[
            AppSpacing.gapLg,
            const Divider(height: 1),
            AppSpacing.gapMd,
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: context.palette.textTertiary,
                ),
                AppSpacing.hGapSm,
                Expanded(
                  child: Text(
                    // The stored friendly message, never the provider's own
                    // error text.
                    job.failure?.message ?? 'The document could not be read.',
                    style: context.text.bodySmall,
                  ),
                ),
              ],
            ),
          ],

          if (job.provider != null) ...[
            AppSpacing.gapSm,
            Text(
              job.usedEmbeddedText
                  ? 'Read from the PDF text layer'
                  : 'Read by ${job.provider}',
              style: context.text.labelSmall
                  ?.copyWith(letterSpacing: 0, color: context.palette.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  static (String, Color, IconData) _statusFor(
    BuildContext context,
    OcrJob job,
  ) {
    switch (job.status) {
      case OcrJobStatus.completed:
        return (
          'Completed',
          context.palette.income,
          Icons.check_circle_outline_rounded,
        );
      case OcrJobStatus.partiallyCompleted:
        return (
          job.confirmedCount == 0 ? 'Awaiting review' : 'Partly imported',
          context.colors.primary,
          Icons.pending_outlined,
        );
      case OcrJobStatus.failed:
        return ('Failed', context.palette.danger, Icons.error_outline_rounded);
      case OcrJobStatus.cancelled:
        return (
          'Cancelled',
          context.palette.textTertiary,
          Icons.cancel_outlined,
        );
      case OcrJobStatus.processing:
      case OcrJobStatus.queued:
        return (
          'Processing',
          context.palette.warning,
          Icons.hourglass_empty_rounded,
        );
    }
  }
}

class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: const [
        CardSkeleton(height: 130),
        SizedBox(height: AppSpacing.md),
        CardSkeleton(height: 130),
        SizedBox(height: AppSpacing.md),
        CardSkeleton(height: 110),
      ],
    );
  }
}
