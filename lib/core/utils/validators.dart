import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/app_config.dart';
import '../constants/app_constants.dart';
import '../errors/app_exception.dart';
import 'money.dart';

/// Client-side validation. Every rule enforced here is also enforced by a
/// PostgreSQL constraint or an RLS policy — this layer exists for immediate
/// feedback, not for security.
class Validators {
  const Validators._();

  static final RegExp _emailPattern = RegExp(
    r'^[\w.!#$%&*+/=?^`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?'
    r'(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$',
  );

  static String? required(String? value, {String field = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$field is required';
    return null;
  }

  static String? email(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Email is required';
    if (!_emailPattern.hasMatch(trimmed)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  /// Minimum 8 characters with at least one letter and one digit. Supabase is
  /// configured with the same minimum length.
  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'Use at least 8 characters';
    if (!v.contains(RegExp('[A-Za-z]'))) {
      return 'Include at least one letter';
    }
    if (!v.contains(RegExp('[0-9]'))) {
      return 'Include at least one number';
    }
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if (value == null || value.isEmpty) return 'Confirm your password';
    if (value != original) return 'Passwords do not match';
    return null;
  }

  static String? fullName(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Name is required';
    if (trimmed.length < 2) return 'Enter your full name';
    if (trimmed.length > 80) return 'Name is too long';
    return null;
  }

  /// Amounts must be present, numeric and strictly greater than zero.
  static String? amount(String? value, {String currency = 'LKR'}) {
    if (value == null || value.trim().isEmpty) return 'Enter an amount';
    final money = Money.tryParse(value, currency);
    if (money == null) return 'Enter a valid amount';
    if (money.isNegative) return 'Amount cannot be negative';
    if (money.isZero) return 'Amount must be greater than zero';
    if (money.minorUnits > 999999999999) return 'That amount is too large';
    return null;
  }

  /// Signed amounts, for an opening balance which may legitimately be negative
  /// (a credit card that already carries debt).
  static String? signedAmount(String? value, {String currency = 'LKR'}) {
    if (value == null || value.trim().isEmpty) return null;
    final money = Money.tryParse(value, currency);
    if (money == null) return 'Enter a valid amount';
    return null;
  }

  static String? accountName(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Account name is required';
    if (trimmed.length > 60) return 'Keep the name under 60 characters';
    return null;
  }

  static String? categoryName(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Category name is required';
    if (trimmed.length > 40) return 'Keep the name under 40 characters';
    return null;
  }

  /// Only the last four digits of a card or account may ever be stored.
  static String? last4(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (!RegExp(r'^\d{4}$').hasMatch(trimmed)) {
      return 'Enter exactly the last 4 digits';
    }
    return null;
  }

  static String? alertThreshold(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return 'Enter a whole number';
    if (parsed < 1 || parsed > 200) return 'Choose a value between 1 and 200';
    return null;
  }

  /// A day of the month for a recurring date like a credit card statement.
  /// Optional, like the other card fields: left blank when the user does not
  /// want a reminder.
  static String? dayOfMonth(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return 'Enter a whole number';
    if (parsed < 1 || parsed > 31) return 'Choose a day between 1 and 31';
    return null;
  }

  static String? reminderDays(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return 'Enter a whole number';
    if (parsed < 0 || parsed > 60) return 'Choose between 0 and 60 days';
    return null;
  }

  /// A transfer must move money between two different accounts.
  static String? transferAccounts(String? fromId, String? toId) {
    if (fromId == null || fromId.isEmpty) return 'Choose the source account';
    if (toId == null || toId.isEmpty) return 'Choose the destination account';
    if (fromId == toId) return 'Choose two different accounts';
    return null;
  }

  /// The sum of split lines must equal the parent transaction amount exactly.
  /// Compared in minor units, so there is no floating point tolerance needed.
  static String? splitTotal(Money total, List<Money> parts) {
    if (parts.isEmpty) return 'Add at least one split line';
    if (parts.any((p) => p.isZero || p.isNegative)) {
      return 'Every split amount must be greater than zero';
    }
    final sum = parts.reduce((a, b) => a + b);
    if (sum == total) return null;
    final difference = total - sum;
    final verb = difference.isPositive ? 'under' : 'over';
    return 'Splits are $verb by ${difference.abs.format()} '
        '(${sum.format()} of ${total.format()})';
  }

  static String? dateRange(DateTime? start, DateTime? end) {
    if (start == null) return 'Choose a start date';
    if (end == null) return 'Choose an end date';
    if (end.isBefore(start)) return 'The end date must be after the start date';
    return null;
  }

  /// A transaction cannot be dated far in the future — that is almost always a
  /// typo or an OCR misread of the year.
  static String? transactionDate(DateTime? date) {
    if (date == null) return 'Choose a date';
    final limit = DateTime.now().add(const Duration(days: 365));
    if (date.isAfter(limit)) return 'That date is too far in the future';
    if (date.isBefore(DateTime(2000))) return 'That date is too far in the past';
    return null;
  }

  static String? targetAmount(String? value, Money current) {
    final base = amount(value, currency: current.currency);
    if (base != null) return base;
    final target = Money.tryParse(value, current.currency)!;
    if (target < current) {
      return 'The target must be at least what you have already saved';
    }
    return null;
  }
}

/// Result of inspecting a file the user picked, before any upload happens.
class FileValidationResult {
  const FileValidationResult({
    required this.fileName,
    required this.extension,
    required this.mimeType,
    required this.sizeBytes,
    required this.isPdf,
  });

  final String fileName;
  final String extension;
  final String mimeType;
  final int sizeBytes;
  final bool isPdf;

  bool get isImage => !isPdf;
}

/// Validates uploads before they leave the device. The Edge Function repeats
/// these checks server-side; a client check alone would be trivially bypassed.
class FileValidator {
  const FileValidator._();

  static const Map<String, String> _mimeByExtension = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'pdf': 'application/pdf',
  };

  /// Magic-number prefixes. A file that claims to be a PDF but does not start
  /// with `%PDF-` is rejected rather than sent to the OCR provider.
  static bool _matchesSignature(List<int> head, String extension) {
    bool startsWith(List<int> sig) {
      if (head.length < sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (head[i] != sig[i]) return false;
      }
      return true;
    }

    switch (extension) {
      case 'pdf':
        return startsWith([0x25, 0x50, 0x44, 0x46]); // %PDF
      case 'png':
        return startsWith([0x89, 0x50, 0x4E, 0x47]);
      case 'jpg':
      case 'jpeg':
        return startsWith([0xFF, 0xD8, 0xFF]);
      case 'webp':
        return head.length >= 12 &&
            startsWith([0x52, 0x49, 0x46, 0x46]) && // RIFF
            head[8] == 0x57 &&
            head[9] == 0x45 &&
            head[10] == 0x42 &&
            head[11] == 0x50; // WEBP
      default:
        return false;
    }
  }

  /// Throws a [FileException] describing, in plain language, what is wrong.
  static FileValidationResult validate({
    required String fileName,
    required int sizeBytes,
    required List<int> headBytes,
  }) {
    final extension =
        p.extension(fileName).replaceFirst('.', '').toLowerCase();

    if (extension.isEmpty || !AppConstants.allowedExtensions.contains(extension)) {
      throw const FileException(
        'That file type is not supported. Upload a JPG, PNG, WEBP or PDF file.',
      );
    }

    if (sizeBytes <= 0) {
      throw const FileException('That file is empty. Choose another file.');
    }

    if (sizeBytes > AppConfig.maxUploadBytes) {
      final mb = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);
      throw FileException(
        'That file is $mb MB. The maximum size is '
        '${AppConfig.maxUploadMb} MB.',
      );
    }

    if (!_matchesSignature(headBytes, extension)) {
      throw const FileException(
        'We could not read that file. It may be damaged — try exporting or '
        'scanning it again.',
      );
    }

    return FileValidationResult(
      fileName: fileName,
      extension: extension,
      mimeType: _mimeByExtension[extension] ?? 'application/octet-stream',
      sizeBytes: sizeBytes,
      isPdf: extension == 'pdf',
    );
  }

  /// Convenience wrapper that reads only the header bytes from disk.
  static Future<FileValidationResult> validateFile(File file) async {
    if (!await file.exists()) {
      throw const FileException('That file could not be found on your device.');
    }
    final length = await file.length();
    final handle = await file.open();
    try {
      final head = await handle.read(16);
      return validate(
        fileName: p.basename(file.path),
        sizeBytes: length,
        headBytes: head,
      );
    } finally {
      await handle.close();
    }
  }
}
