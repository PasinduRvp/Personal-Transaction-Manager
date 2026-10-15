import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../shared/models/document.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/providers/ocr_providers.dart';
import '../../../shared/providers/repository_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/transaction_tile.dart';
import '../../ocr/presentation/import_source_sheet.dart';
import '../../ocr/presentation/widgets/document_preview.dart';

/// Every uploaded receipt, statement and invoice.
class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documents = ref.watch(documentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents'),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.importHistory),
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Import history',
          ),
          IconButton(
            onPressed: () => ImportSourceSheet.show(context),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Upload document',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(documentsProvider),
        child: documents.view(
          (data) => data.isEmpty
              ? EmptyState(
                  icon: Icons.folder_outlined,
                  title: 'No documents yet',
                  message: 'Receipts and statements you upload are kept here, '
                      'privately, so only you can open them.',
                  actionLabel: 'Upload document',
                  onAction: () => ImportSourceSheet.show(context),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(AppSpacing.page),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: AppSpacing.md,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: data.length,
                  itemBuilder: (context, index) =>
                      _DocumentTile(document: data[index]),
                ),
          loading: const _DocumentsSkeleton(),
          onRetry: () => ref.invalidate(documentsProvider),
        ),
      ),
    );
  }
}

class _DocumentTile extends ConsumerWidget {
  const _DocumentTile({required this.document});

  final FinoraDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => context.push(AppRoutes.documentDetail(document.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.lg),
              ),
              child: _Thumbnail(document: document),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.fileName,
                  style: context.text.labelLarge?.copyWith(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${DateDisplay.relative(document.createdAt)} · '
                  '${document.readableSize}',
                  style: context.text.labelSmall?.copyWith(letterSpacing: 0),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends ConsumerWidget {
  const _Thumbnail({required this.document});

  final FinoraDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (document.isPdf) {
      return ColoredBox(
        color: context.palette.surfaceAlt,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.picture_as_pdf_outlined,
                size: 34,
                color: context.palette.danger,
              ),
              if (document.pageCount != null) ...[
                AppSpacing.gapXs,
                Text(
                  '${document.pageCount} '
                  'page${document.pageCount == 1 ? '' : 's'}',
                  style: context.text.labelSmall?.copyWith(letterSpacing: 0),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return DocumentPreview(document: document, height: double.infinity);
  }
}

/// One document: preview, metadata, and the transactions it produced.
class DocumentDetailScreen extends ConsumerWidget {
  const DocumentDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(documentByIdProvider(documentId));

    return Scaffold
      (
      appBar: AppBar(
        title: const Text('Document'),
        actions: [
          document.maybeWhen(
            data: (data) => _DocumentMenu(document: data),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: document.view(
        (data) => _DocumentBody(document: data),
        onRetry: () => ref.invalidate(documentByIdProvider(documentId)),
      ),
    );
  }
}

class _DocumentBody extends ConsumerWidget {
  const _DocumentBody({required this.document});

  final FinoraDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactions = ref.watch(documentTransactionsProvider(document.id));

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        DocumentPreview(
          document: document,
          height: 280,
          onTap: () => DocumentViewerScreen.open(context, document: document),
        ),
        AppSpacing.gapLg,

        AppCard(
          child: Column(
            children: [
              DetailRow(
                label: 'File name',
                icon: Icons.insert_drive_file_outlined,
                value: document.fileName,
                isMultiline: true,
              ),
              const Divider(height: 1),
              DetailRow(
                label: 'Type',
                icon: Icons.category_outlined,
                value: document.documentType.label,
              ),
              const Divider(height: 1),
              DetailRow(
                label: 'Size',
                icon: Icons.data_usage_rounded,
                value: document.readableSize,
              ),
              if (document.pageCount != null) ...[
                const Divider(height: 1),
                DetailRow(
                  label: 'Pages',
                  icon: Icons.layers_outlined,
                  value: '${document.pageCount}',
                ),
              ],
              const Divider(height: 1),
              DetailRow(
                label: 'Uploaded',
                icon: Icons.upload_file_outlined,
                value: DateDisplay.dateTime(document.createdAt),
              ),
              const Divider(height: 1),
              DetailRow(
                label: 'Reading status',
                icon: Icons.document_scanner_outlined,
                valueWidget: AppChipLabel(
                  label: document.ocrStatus.label,
                  color: switch (document.ocrStatus) {
                    OcrJobStatus.completed ||
                    OcrJobStatus.partiallyCompleted =>
                      context.palette.income,
                    OcrJobStatus.failed => context.palette.danger,
                    OcrJobStatus.cancelled => context.palette.textTertiary,
                    _ => context.palette.warning,
                  },
                  dense: true,
                ),
              ),
            ],
          ),
        ),
        AppSpacing.gapLg,

        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: context.palette.surfaceAlt,
            borderRadius: AppRadius.mdAll,
          ),
          child: Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: context.palette.textSecondary,
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: Text(
                  'Stored privately. Only you can open this file, and links to '
                  'it expire after a few minutes.',
                  style: context.text.bodySmall,
                ),
              ),
            ],
          ),
        ),

        AppSpacing.gapXl,
        Text('Transactions from this document', style: context.text.titleMedium),
        AppSpacing.gapMd,
        transactions.view(
          (data) => data.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No transactions yet',
                  message: 'Nothing from this document has been confirmed.',
                  compact: true,
                )
              : AppCard(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Column(
                    children: [
                      for (final transaction in data)
                        TransactionMiniTile(
                          transaction: transaction,
                          onTap: () => context.push(
                            AppRoutes.transactionDetail(transaction.id),
                          ),
                        ),
                    ],
                  ),
                ),
          loading: const CardSkeleton(height: 90),
          errorCompact: true,
        ),
        AppSpacing.gapXl,

        RawTextPanel(documentId: document.id),
        AppSpacing.gapXxl,
      ],
    );
  }
}

/// Transactions that reference a document.
final documentTransactionsProvider =
    FutureProvider.family<List<Transaction>, String>((ref, documentId) {
  return ref.watch(transactionRepositoryProvider).fetchByDocument(documentId);
});

class _DocumentMenu extends ConsumerWidget {
  const _DocumentMenu({required this.document});

  final FinoraDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (value) async {
        switch (value) {
          case 'reread':
            await _reread(context, ref);
          case 'delete':
            await _delete(context, ref);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'reread',
          child: ListTile(
            leading: Icon(Icons.refresh_rounded),
            title: Text('Read again'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(
              Icons.delete_outline_rounded,
              color: context.palette.danger,
            ),
            title: Text(
              'Delete',
              style: TextStyle(color: context.palette.danger),
            ),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      ],
    );
  }

  Future<void> _reread(BuildContext context, WidgetRef ref) async {
    final confirmed = await AppFeedback.confirm(
      context,
      title: 'Read this document again?',
      message: 'Finora will re-extract the transactions. Your previous import '
          'stays in the history.',
      confirmLabel: 'Read again',
    );
    if (!confirmed || !context.mounted) return;

    // Clear any state from a previous import before starting a new job, so the
    // processing screen does not briefly show the old document's candidates.
    ref.read(importControllerProvider.notifier).reset();

    final job = await AppFeedback.runWithProgress(
      context,
      progressMessage: 'Reading the document again…',
      action: () => ref
          .read(ocrRepositoryProvider)
          .startJob(documentId: document.id, force: true),
    );

    if (job == null || !context.mounted) return;

    ref.invalidate(importHistoryProvider);
    ref.invalidate(documentByIdProvider(document.id));
    context.push(AppRoutes.ocrReviewJob(job.id));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final attachments = await ref
        .read(documentRepositoryProvider)
        .attachmentCount(document.id);

    if (!context.mounted) return;

    final confirmed = await AppFeedback.confirm(
      context,
      title: 'Delete document?',
      message: 'The file and the text read from it will be removed.',
      confirmLabel: 'Delete',
      isDestructive: true,
      consequences: [
        // Deleting evidence must not delete the record of spending.
        if (attachments > 0)
          '$attachments transaction${attachments == 1 ? '' : 's'} '
              'will keep existing, without an attached receipt.',
        'This cannot be undone.',
      ],
    );
    if (!confirmed || !context.mounted) return;

    final done = await AppFeedback.runWithProgress(
      context,
      progressMessage: 'Deleting…',
      successMessage: 'Document deleted',
      action: () async {
        await ref.read(documentRepositoryProvider).delete(document);
        return true;
      },
    );

    if (done == true && context.mounted) {
      ref.invalidate(documentsProvider);
      ref.invalidate(importHistoryProvider);
      context.pop();
    }
  }
}

class _DocumentsSkeleton extends StatelessWidget {
  const _DocumentsSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.page),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        childAspectRatio: 0.78,
      ),
      itemCount: 6,
      itemBuilder: (context, index) =>
          const CardSkeleton(height: double.infinity),
    );
  }
}
