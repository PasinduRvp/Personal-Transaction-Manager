import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/services/image_preprocessor.dart';

/// A picked image, already compressed for storage.
class PickedImage {
  const PickedImage({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}

/// Picks an image from the camera or the gallery.
///
/// Compresses before returning, because the callers here (avatars, attachments)
/// display at small sizes and a full-resolution original would waste the user's
/// bandwidth and storage quota for no visible gain.
class ImageSourcePicker {
  const ImageSourcePicker._();

  static Future<PickedImage?> pick(
    BuildContext context, {
    int maxBytes = 400 * 1024,
  }) async {
    final source = await _chooseSource(context);
    if (source == null) return null;

    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      maxWidth: 1400,
      maxHeight: 1400,
      imageQuality: 90,
    );
    if (file == null) return null;

    final original = await file.readAsBytes();
    final compressed = await ImagePreprocessor.compressForStorage(
      original,
      maxBytes: maxBytes,
    );

    return PickedImage(
      bytes: compressed,
      fileName: file.name.isEmpty ? 'image.jpg' : file.name,
    );
  }

  static Future<ImageSource?> _chooseSource(BuildContext context) async {
    // No camera on desktop or web, so the sheet would offer a dead option.
    final hasCamera = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    if (!hasCamera) return ImageSource.gallery;

    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }
}
