import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/models/ocr_job.dart';
import '../../../shared/providers/ocr_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';

/// Shows the pipeline running.
///
/// The stages are named rather than hidden behind a spinner, because reading a
/// multi-page statement takes long enough that an undifferentiated wait feels
/// broken. Each stage is real: upload, OCR, extraction, review preparation.
class ImportProcessingScreen extends ConsumerWidget {
  const ImportProcessingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);

    // As soon as candidates are ready, move on — the user came here to review
    // them, not to watch a progress list.
    ref.listen(importControllerProvider, (previous, next) {
      if (previous?.stage != next.stage &&
          next.stage == ImportStage.readyForReview) {
        final jobId = next.job?.id;
        if (jobId == null) return;

        if (next.candidates.isEmpty) return;

        context.pushReplacement(AppRoutes.ocrReviewJob(jobId));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reading document'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => _cancel(context, ref, state),
          tooltip: 'Cancel',
        ),
      ),
      body: SafeArea(
        child: switch (state.stage) {
          ImportStage.failed => _FailureView(state: state),
          ImportStage.readyForReview when state.candidates.isEmpty =>
            _NoTransactionsView(state: state),
          _ => _ProgressView(state: state),
        },
      ),
    );
  }

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    ImportState state,
  ) async {
    if (state.isBusy) {
      final confirmed = await AppFeedback.confirm(
        context,
        title: 'Stop reading this document?',
        message: 'The uploaded file stays in your documents, and you can read '
            'it again later.',
        confirmLabel: 'Stop',
      );
      if (!confirmed || !context.mounted) return;
    }

    await ref.read(importControllerProvider.notifier).cancel();
    if (context.mounted) context.pop();
  }
}

class _ProgressView extends StatelessWidget {
  const _ProgressView({required this.state});

  final ImportState state;

  @override
  Widget build(BuildContext context) {
    final job = state.job;
    final stages = _stagesFor(state);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AppSpacing.gapXl,
        Center(
          child: SizedBox(
            width: 92,
            height: 92,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 92,
                  height: 92,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    // Indeterminate until the server reports page progress,
                    // then determinate — a fake percentage would be worse than
                    // an honest spinner.
                    value: job == null || job.pageCount == null
                        ? null
                        : job.progressFraction,
                    backgroundColor: context.palette.surfaceAlt,
                  ),
                ),
                Icon(
                  Icons.document_scanner_outlined,
                  size: 34,
                  color: context.colors.primary,
                ),
              ],
            ),
          ),
        ),
        AppSpacing.gapXxl,

        Center(
          child: Text(
            'Processing document…',
            style: context.text.titleLarge,
          ),
        ),
        AppSpacing.gapSm,
        Center(
          child: Text(
            state.document?.fileName ?? 'Please wait',
            style: context.text.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
        AppSpacing.gapXxl,

        AppCard(
          child: Column(
            children: [
              for (var i = 0; i < stages.length; i++) ...[
                if (i > 0) AppSpacing.gapLg,
                _StageRow(stage: stages[i]),
              ],
            ],
          ),
        ),

        if (job?.usedEmbeddedText == true) ...[
          AppSpacing.gapLg,
          _InfoNote(
            icon: Icons.bolt_outlined,
            message: 'This PDF already contained text, so it was read directly '
                'without scanning — faster and more accurate.',
          ),
        ],

        if (state.isReupload) ...[
          AppSpacing.gapLg,
          _InfoNote(
            icon: Icons.content_copy_outlined,
            message: 'You have uploaded this same file before. Check for '
                'duplicates on the review screen.',
          ),
        ],

        AppSpacing.gapXxl,
        Center(
          child: Text(
            'Nothing is saved until you review and confirm it.',
            style: context.text.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  /// Derives the stage list from the local pipeline stage, falling back to the
  /// job's own view once the server takes over.
  static List<OcrStage> _stagesFor(ImportState state) {
    final job = state.job;
    if (job != null) return job.stages;

    return switch (state.stage) {
      ImportStage.validating => const [
          OcrStage('Checking file', false, true),
          OcrStage('Uploading', false, false),
          OcrStage('Reading document', false, false),
          OcrStage('Extracting transactions', false, false),
        ],
      ImportStage.uploading => const [
          OcrStage('Checking file', true, false),
          OcrStage('Uploading', false, true),
          OcrStage('Reading document', false, false),
          OcrStage('Extracting transactions', false, false),
        ],
      _ => const [
          OcrStage('Checking file', true, false),
          OcrStage('Uploading', true, false),
          OcrStage('Reading document', false, true),
          OcrStage('Extracting transactions', false, false),
        ],
    };
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({required this.stage});

  final OcrStage stage;

  @override
  Widget build(BuildContext context) {
    final Widget leading;
    if (stage.isComplete) {
      leading = Icon(
        Icons.check_circle_rounded,
        size: 22,
        color: context.palette.income,
      );
    } else if (stage.isActive) {
      leading = SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          color: context.colors.primary,
        ),
      );
    } else {
      leading = Icon(
        Icons.radio_button_unchecked_rounded,
        size: 22,
        color: context.palette.textTertiary,
      );
    }

    return Row(
      children: [
        leading,
        AppSpacing.hGapLg,
        Expanded(
          child: Text(
            stage.label,
            style: stage.isComplete || stage.isActive
                ? context.text.titleSmall
                : context.text.bodyMedium
                    ?.copyWith(color: context.palette.textTertiary),
          ),
        ),
      ],
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.palette.surfaceAlt,
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.palette.textSecondary),
          AppSpacing.hGapMd,
          Expanded(child: Text(message, style: context.text.bodySmall)),
        ],
      ),
    );
  }
}

/// The document was read, but no transactions were found in it.
///
/// A distinct state from failure: the read worked, there was just nothing to
/// import, and conflating the two would send the user chasing a problem that
/// does not exist.
class _NoTransactionsView extends ConsumerWidget {
  const _NoTransactionsView({required this.state});

  final ImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AppSpacing.gapXxl,
        Center(
          child: IconBadge(
            icon: Icons.search_off_rounded,
            color: context.palette.warning,
            size: 72,
          ),
        ),
        AppSpacing.gapXl,
        Text(
          'No transactions found',
          style: context.text.titleLarge,
          textAlign: TextAlign.center,
        ),
        AppSpacing.gapSm,
        Text(
          'We read ${state.document?.fileName ?? 'the document'} but could not '
          'find anything that looked like a transaction.',
          style: context.text.bodyMedium,
          textAlign: TextAlign.center,
        ),
        AppSpacing.gapXxl,

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('What usually helps', style: context.text.titleSmall),
              AppSpacing.gapMd,
              for (final tip in const [
                'Make sure the total and the date are visible in the image',
                'Avoid shadows and glare across the figures',
                'Photograph the document straight on, filling the frame',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('•  ', style: context.text.bodyMedium),
                      Expanded(
                        child: Text(tip, style: context.text.bodyMedium),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        AppSpacing.gapXxl,

        FilledButton.icon(
          onPressed: () {
            ref.read(importControllerProvider.notifier).reset();
            context.pushReplacement(AppRoutes.transactionAdd);
          },
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Add it manually instead'),
        ),
        AppSpacing.gapSm,
        OutlinedButton.icon(
          onPressed: () =>
              ref.read(importControllerProvider.notifier).retry(),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Read the document again'),
        ),
        AppSpacing.gapSm,
        TextButton(
          onPressed: () {
            ref.read(importControllerProvider.notifier).reset();
            context.pop();
          },
          child: const Text('Done'),
        ),
      ],
    );
  }
}

/// OCR failed. Shows the friendly reason and what to try, never the underlying
/// provider error.
class _FailureView extends ConsumerWidget {
  const _FailureView({required this.state});

  final ImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failure = state.failure;
    final suggestions =
        failure is OcrException ? failure.suggestions : const <String>[];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AppSpacing.gapXxl,
        Center(
          child: IconBadge(
            icon: Icons.document_scanner_outlined,
            color: context.palette.danger,
            size: 72,
          ),
        ),
        AppSpacing.gapXl,
        Text(
          "We couldn't read this document clearly",
          style: context.text.titleLarge,
          textAlign: TextAlign.center,
        ),
        AppSpacing.gapSm,
        Text(
          failure?.message ?? 'Something went wrong while reading the document.',
          style: context.text.bodyMedium,
          textAlign: TextAlign.center,
        ),
        AppSpacing.gapXxl,

        if (suggestions.isNotEmpty)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Try uploading', style: context.text.titleSmall),
                AppSpacing.gapMd,
                for (final suggestion in suggestions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('•  ', style: context.text.bodyMedium),
                        Expanded(
                          child: Text(
                            suggestion,
                            style: context.text.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        AppSpacing.gapXxl,

        if (state.document != null)
          OutlinedButton.icon(
            onPressed: () =>
                ref.read(importControllerProvider.notifier).retry(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try reading it again'),
          ),
        AppSpacing.gapSm,
        FilledButton.icon(
          onPressed: () {
            ref.read(importControllerProvider.notifier).reset();
            context.pushReplacement(AppRoutes.transactionAdd);
          },
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Add the transaction manually'),
        ),
        AppSpacing.gapSm,
        TextButton(
          onPressed: () {
            ref.read(importControllerProvider.notifier).reset();
            context.pop();
          },
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
