import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/models/document.dart';
import '../../../../shared/providers/ocr_providers.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/state_views.dart';

/// Shows the uploaded document beside the extracted fields.
///
/// Having the original visible is the whole point of the review step: the user
/// is checking the parse against the document, and making them navigate away to
/// see it would defeat that.
class DocumentPreview extends ConsumerWidget {
  const DocumentPreview({
    super.key,
    required this.document,
    this.height = 220,
    this.onTap,
  });

  final FinoraDocument document;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (document.isPdf) {
      return _PdfPlaceholder(document: document, onTap: onTap);
    }

    final preview = ref.watch(documentPreviewProvider(document));

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: AppRadius.lgAll,
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: preview.when(
            data: (bytes) => bytes == null
                ? _PreviewUnavailable(document: document)
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(
                        bytes,
                        fit: BoxFit.cover,
                        // Decoded at tile size rather than full resolution: a
                        // 12-megapixel phone photo would otherwise cost about
                        // 48 MB of image cache to draw a 220px card.
                        cacheHeight: (height * 2).round(),
                        errorBuilder: (context, _, __) =>
                            _PreviewUnavailable(document: document),
                      ),
                      if (onTap != null)
                        Positioned(
                          right: AppSpacing.sm,
                          bottom: AppSpacing.sm,
                          child: _ZoomHint(),
                        ),
                    ],
                  ),
            loading: () => Skeleton(
              height: height,
              borderRadius: BorderRadius.zero,
            ),
            error: (_, __) => _PreviewUnavailable(document: document),
          ),
        ),
      ),
    );
  }
}

class _ZoomHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.zoom_in_rounded, size: 14, color: Colors.white),
          AppSpacing.hGapXs,
          Text(
            'Tap to enlarge',
            style: context.text.labelSmall
                ?.copyWith(color: Colors.white, letterSpacing: 0),
          ),
        ],
      ),
    );
  }
}

class _PdfPlaceholder extends StatelessWidget {
  const _PdfPlaceholder({required this.document, this.onTap});

  final FinoraDocument document;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          IconBadge(
            icon: Icons.picture_as_pdf_outlined,
            color: context.palette.danger,
            size: 46,
          ),
          AppSpacing.hGapLg,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.fileName,
                  style: context.text.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    document.readableSize,
                    if (document.pageCount != null)
                      '${document.pageCount} '
                          'page${document.pageCount == 1 ? '' : 's'}',
                  ].join(' · '),
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(
              Icons.open_in_new_rounded,
              size: 20,
              color: context.palette.textTertiary,
            ),
        ],
      ),
    );
  }
}

class _PreviewUnavailable extends StatelessWidget {
  const _PreviewUnavailable({required this.document});

  final FinoraDocument document;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.palette.surfaceAlt,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              document.icon,
              size: 30,
              color: context.palette.textTertiary,
            ),
            AppSpacing.gapSm,
            Text(
              'Preview unavailable',
              style: context.text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// A full-screen, zoomable view of the document.
class DocumentViewerScreen extends ConsumerWidget {
  const DocumentViewerScreen({super.key, required this.document});

  final FinoraDocument document;

  static Future<void> open(
    BuildContext context, {
    required FinoraDocument document,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DocumentViewerScreen(document: document),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(documentBytesProvider(document));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          document.fileName,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: bytes.when(
        data: (data) => document.isPdf
            ? _PdfNotViewable(document: document)
            : InteractiveViewer(
                // Generous zoom, because the reason to open this is usually to
                // read a figure the parser could not. Full resolution here, not
                // downscaled: zooming into a decoded thumbnail would show the
                // user a blur where the figure should be.
                maxScale: 6,
                child: Center(
                  child: Image.memory(
                    data,
                    fit: BoxFit.contain,
                    errorBuilder: (context, _, __) => const Center(
                      child: Text(
                        'Could not load this document',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ),
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: ErrorStateView(
              error: error,
              onRetry: () => ref.invalidate(documentBytesProvider(document)),
            ),
          ),
        ),
      ),
    );
  }
}

/// PDFs are not rendered in-app: shipping a PDF renderer for a preview would add
/// a large native dependency, and the platform viewer does this better.
class _PdfNotViewable extends StatelessWidget {
  const _PdfNotViewable({required this.document});

  final FinoraDocument document;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.picture_as_pdf_outlined,
              size: 56,
              color: Colors.white54,
            ),
            AppSpacing.gapXl,
            Text(
              document.fileName,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            AppSpacing.gapSm,
            const Text(
              'Open this PDF from your documents to view it in your device '
              'viewer.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// The raw OCR text, collapsed by default.
///
/// Kept available because when a parse looks wrong, the raw text is what tells
/// the user whether the document was misread or merely misinterpreted.
class RawTextPanel extends ConsumerStatefulWidget {
  const RawTextPanel({super.key, required this.documentId});

  final String documentId;

  @override
  ConsumerState<RawTextPanel> createState() => _RawTextPanelState();
}

class _RawTextPanelState extends ConsumerState<RawTextPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: AppRadius.smAll,
            child: Row(
              children: [
                Icon(
                  Icons.subject_rounded,
                  size: 18,
                  color: context.palette.textSecondary,
                ),
                AppSpacing.hGapMd,
                Expanded(
                  child: Text(
                    'What we read from the document',
                    style: context.text.titleSmall,
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: context.palette.textSecondary,
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            AppSpacing.gapMd,
            _RawTextBody(documentId: widget.documentId),
          ],
        ],
      ),
    );
  }
}

class _RawTextBody extends ConsumerWidget {
  const _RawTextBody({required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(ocrResultsProvider(documentId));

    return results.view(
      (data) {
        if (data.isEmpty) {
          return Text('No text was stored.', style: context.text.bodySmall);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final result in data) ...[
              if (data.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    'Page ${result.pageNumber ?? 1}'
                    '${result.confidence == null ? '' : ' · ${(result.confidence! * 100).round()}% confidence'}',
                    style: context.text.labelSmall
                        ?.copyWith(letterSpacing: 0),
                  ),
                ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: context.palette.surfaceAlt,
                  borderRadius: AppRadius.smAll,
                ),
                child: SelectableText(
                  result.rawText,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['Courier New'],
                    fontSize: 11.5,
                    height: 1.45,
                    color: context.palette.textSecondary,
                  ),
                ),
              ),
            ],
            Text(
              'This is the original text and never changes, even when you '
              'correct a field.',
              style: context.text.bodySmall,
            ),
          ],
        );
      },
      loading: const LoadingView(compact: true),
      errorCompact: true,
    );
  }
}
