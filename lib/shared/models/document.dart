import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../core/constants/enums.dart';
import 'json_map.dart';

/// A document at `users/{uid}/documents/{id}` — the original file the user
/// uploaded.
///
/// The stored file is never modified. Preprocessing (rotation, contrast,
/// compression) happens on a copy that is sent to the OCR provider, so the
/// receipt the user can open later is exactly what they uploaded.
class FinoraDocument extends Equatable {
  const FinoraDocument({
    required this.id,
    required this.userId,
    required this.fileName,
    required this.storagePath,
    required this.mimeType,
    required this.fileSize,
    this.pageCount,
    this.documentType = DocumentType.unknown,
    this.ocrStatus = OcrJobStatus.queued,
    this.checksum,
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String fileName;

  /// Full object path in the bucket, always
  /// `documents/<uid>/<document_id>/<file>`.
  ///
  /// There is one bucket under Firebase, so the folder is part of this path
  /// rather than a separate field.
  final String storagePath;
  final String mimeType;
  final int fileSize;
  final int? pageCount;
  final DocumentType documentType;

  /// Mirrors the latest OCR job's status so lists can be rendered from one
  /// query.
  final OcrJobStatus ocrStatus;

  /// SHA-256 of the uploaded bytes, used to spot a re-upload of the same file.
  final String? checksum;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isPdf => mimeType == 'application/pdf';
  bool get isImage => mimeType.startsWith('image/');

  String get extension {
    final dot = fileName.lastIndexOf('.');
    return dot == -1 ? '' : fileName.substring(dot + 1).toLowerCase();
  }

  String get readableSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(0)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData get icon => isPdf
      ? Icons.picture_as_pdf_outlined
      : Icons.image_outlined;

  factory FinoraDocument.fromJson(Json json) => FinoraDocument(
        id: json.str('id'),
        userId: json.str('user_id'),
        fileName: json.str('file_name'),
        storagePath: json.str('storage_path'),
        mimeType: json.str('mime_type', fallback: 'application/octet-stream'),
        fileSize: json.intVal('file_size'),
        pageCount: json.intOrNull('page_count'),
        documentType: DocumentType.fromWire(json.strOrNull('document_type')),
        ocrStatus: OcrJobStatus.fromWire(json.strOrNull('ocr_status')),
        checksum: json.strOrNull('checksum'),
        isArchived: json.boolVal('is_archived'),
        createdAt: json.dateVal('created_at'),
        updatedAt: json.dateVal('updated_at'),
      );

  Json toInsertJson() => compactJson({
        'id': id,
        'file_name': fileName,
        'storage_path': storagePath,
        'mime_type': mimeType,
        'file_size': fileSize,
        'page_count': pageCount,
        'document_type': documentType.wire,
        'ocr_status': ocrStatus.wire,
        'checksum': checksum,
      });

  FinoraDocument copyWith({
    String? fileName,
    int? pageCount,
    DocumentType? documentType,
    OcrJobStatus? ocrStatus,
    bool? isArchived,
  }) =>
      FinoraDocument(
        id: id,
        userId: userId,
        fileName: fileName ?? this.fileName,
        storagePath: storagePath,
        mimeType: mimeType,
        fileSize: fileSize,
        pageCount: pageCount ?? this.pageCount,
        documentType: documentType ?? this.documentType,
        ocrStatus: ocrStatus ?? this.ocrStatus,
        checksum: checksum,
        isArchived: isArchived ?? this.isArchived,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  @override
  List<Object?> get props => [
        id,
        fileName,
        storagePath,
        mimeType,
        fileSize,
        pageCount,
        documentType,
        ocrStatus,
        isArchived,
      ];
}
