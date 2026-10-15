import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/providers/ocr_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';

/// Where a document comes from.
///
/// Camera, gallery, image file and PDF, as four explicit choices rather than one
/// ambiguous "attach" button — the user knows which they want, and each maps to a
/// different platform picker.
class ImportSourceSheet extends ConsumerWidget {
  const ImportSourceSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => const ImportSourceSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Import a document', style: context.text.titleLarge),
            AppSpacing.gapSm,
            Text(
              'Finora reads the document and shows you what it found. Nothing '
              'is saved until you confirm it.',
              style: context.text.bodySmall,
            ),
            AppSpacing.gapXl,

            // The camera is only offered where one exists; on desktop and web
            // it would open a picker that cannot work.
            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
              _SourceTile(
                icon: Icons.photo_camera_outlined,
                title: 'Take a photo',
                subtitle: 'Photograph a receipt or bill',
                onTap: () => _pickFromCamera(context, ref),
              ),
            _SourceTile(
              icon: Icons.photo_library_outlined,
              title: 'Choose from gallery',
              subtitle: 'A photo you already took',
              onTap: () => _pickFromGallery(context, ref),
            ),
            _SourceTile(
              icon: Icons.image_outlined,
              title: 'Image file',
              subtitle: 'JPG, PNG or WEBP',
              onTap: () => _pickFile(
                context,
                ref,
                AppConstants.allowedImageExtensions,
              ),
            ),
            _SourceTile(
              icon: Icons.picture_as_pdf_outlined,
              title: 'PDF document',
              subtitle: 'Bank statement or invoice',
              onTap: () => _pickFile(
                context,
                ref,
                AppConstants.allowedDocumentExtensions,
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
                    Icons.info_outline_rounded,
                    size: 16,
                    color: context.palette.textSecondary,
                  ),
                  AppSpacing.hGapMd,
                  Expanded(
                    child: Text(
                      'Up to ${AppConfig.maxUploadMb} MB. Documents are stored '
                      'privately and only you can open them.',
                      style: context.text.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFromCamera(BuildContext context, WidgetRef ref) async {
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        // Captured at a sane size rather than full sensor resolution: a 12 MP
        // receipt photo is slower to upload and no more readable.
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 92,
      );
      if (photo == null) return;

      final bytes = await photo.readAsBytes();
      if (!context.mounted) return;
      await _start(context, ref, bytes, _fileNameFor(photo.name, '.jpg'));
    } on Object catch (error) {
      if (context.mounted) AppFeedback.showError(context, error);
    }
  }

  Future<void> _pickFromGallery(BuildContext context, WidgetRef ref) async {
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 92,
      );
      if (photo == null) return;

      final bytes = await photo.readAsBytes();
      if (!context.mounted) return;
      await _start(context, ref, bytes, _fileNameFor(photo.name, '.jpg'));
    } on Object catch (error) {
      if (context.mounted) AppFeedback.showError(context, error);
    }
  }

  Future<void> _pickFile(
    BuildContext context,
    WidgetRef ref,
    List<String> extensions,
  ) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions,
        // Needed so the bytes are available on every platform, including web
        // where there is no file path.
        withData: true,
      );

      final file = result?.files.firstOrNull;
      if (file == null) return;

      final bytes = file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());

      if (bytes == null) {
        throw const FileException(
          'That file could not be read. Try choosing it again.',
        );
      }

      if (!context.mounted) return;
      await _start(context, ref, Uint8List.fromList(bytes), file.name);
    } on Object catch (error) {
      if (context.mounted) AppFeedback.showError(context, error);
    }
  }

  /// Closes the sheet, then starts the pipeline and opens the processing screen.
  Future<void> _start(
    BuildContext context,
    WidgetRef ref,
    Uint8List bytes,
    String fileName,
  ) async {
    if (!context.mounted) return;
    Navigator.of(context).pop();

    final controller = ref.read(importControllerProvider.notifier);
    // Not awaited: the processing screen watches the controller's state, so it
    // can show the upload and read stages as they happen instead of appearing
    // only once everything is finished.
    controller.importFile(bytes: bytes, fileName: fileName);

    if (context.mounted) context.push(AppRoutes.importDocument);
  }

  /// Camera captures often arrive with an unhelpful name; give them one that
  /// means something in the documents list.
  static String _fileNameFor(String original, String fallbackExtension) {
    final extension = p.extension(original);
    if (extension.isNotEmpty) return original;
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp('[:.]'), '-')
        .substring(0, 19);
    return 'receipt_$stamp$fallbackExtension';
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            IconBadge(icon: icon, color: context.colors.primary, size: 42),
            AppSpacing.hGapLg,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.titleSmall),
                  const SizedBox(height: 2),
                  Text(subtitle, style: context.text.bodySmall),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: context.palette.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
