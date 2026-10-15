import 'package:finora/core/config/app_config.dart';
import 'package:finora/core/errors/app_exception.dart';
import 'package:finora/core/utils/money.dart';
import 'package:finora/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Validators.email', () {
    test('accepts ordinary addresses', () {
      expect(Validators.email('user@example.com'), isNull);
      expect(Validators.email('first.last+tag@sub.example.co.uk'), isNull);
    });

    test('rejects malformed addresses', () {
      expect(Validators.email('not-an-email'), isNotNull);
      expect(Validators.email('missing@domain'), isNotNull);
      expect(Validators.email('@example.com'), isNotNull);
      expect(Validators.email(''), isNotNull);
      expect(Validators.email(null), isNotNull);
    });
  });

  group('Validators.password', () {
    test('requires length, a letter and a digit', () {
      expect(Validators.password('Passw0rd'), isNull);
      expect(Validators.password('short1'), isNotNull);
      expect(Validators.password('alllettersnodigits'), isNotNull);
      expect(Validators.password('12345678'), isNotNull);
    });
  });

  group('Validators.amount', () {
    test('accepts a positive amount', () {
      expect(Validators.amount('1250.00'), isNull);
      expect(Validators.amount('8,450'), isNull);
    });

    test('rejects zero, because a transaction of nothing is not a transaction',
        () {
      expect(Validators.amount('0'), isNotNull);
      expect(Validators.amount('0.00'), isNotNull);
    });

    test('rejects negatives and nonsense', () {
      expect(Validators.amount('-100'), isNotNull);
      expect(Validators.amount('abc'), isNotNull);
      expect(Validators.amount(''), isNotNull);
    });

    test('rejects an amount too large for the numeric column', () {
      expect(Validators.amount('99999999999999'), isNotNull);
    });
  });

  group('Validators.signedAmount', () {
    test('allows a negative opening balance', () {
      // A credit card can legitimately start in debt.
      expect(Validators.signedAmount('-42000'), isNull);
      expect(Validators.signedAmount('0'), isNull);
    });
  });

  group('Validators.last4', () {
    test('accepts exactly four digits or nothing', () {
      expect(Validators.last4('4321'), isNull);
      expect(Validators.last4(''), isNull);
      expect(Validators.last4(null), isNull);
    });

    test('rejects anything that is not four digits', () {
      expect(Validators.last4('432'), isNotNull);
      expect(Validators.last4('43210'), isNotNull);
      expect(Validators.last4('abcd'), isNotNull);
      // A full card number must never be accepted here.
      expect(Validators.last4('4321432143214321'), isNotNull);
    });
  });

  group('Validators.transferAccounts', () {
    test('requires two different accounts', () {
      expect(Validators.transferAccounts('a', 'b'), isNull);
      expect(Validators.transferAccounts('a', 'a'), isNotNull);
      expect(Validators.transferAccounts(null, 'b'), isNotNull);
      expect(Validators.transferAccounts('a', null), isNotNull);
    });
  });

  group('Validators.splitTotal', () {
    test('accepts splits that reconcile exactly', () {
      final total = Money.fromMajor(10000);
      final parts = [
        Money.fromMajor(6000),
        Money.fromMajor(2500),
        Money.fromMajor(1500),
      ];
      expect(Validators.splitTotal(total, parts), isNull);
    });

    test('reports the shortfall when splits are under', () {
      final error = Validators.splitTotal(
        Money.fromMajor(10000),
        [Money.fromMajor(6000), Money.fromMajor(2500)],
      );
      expect(error, isNotNull);
      expect(error, contains('under'));
      expect(error, contains('1,500'));
    });

    test('reports the excess when splits are over', () {
      final error = Validators.splitTotal(
        Money.fromMajor(10000),
        [Money.fromMajor(6000), Money.fromMajor(5000)],
      );
      expect(error, isNotNull);
      expect(error, contains('over'));
    });

    test('rejects an empty or non-positive split set', () {
      expect(Validators.splitTotal(Money.fromMajor(100), []), isNotNull);
      expect(
        Validators.splitTotal(
          Money.fromMajor(100),
          [Money.fromMajor(100), Money.zero()],
        ),
        isNotNull,
      );
    });

    test('detects a one-cent discrepancy', () {
      // The whole point of integer minor units: this must not pass.
      final error = Validators.splitTotal(
        Money.fromMajor(10),
        [Money.fromMajor(3.33), Money.fromMajor(3.33), Money.fromMajor(3.33)],
      );
      expect(error, isNotNull);
    });
  });

  group('Validators.transactionDate', () {
    test('accepts today and the recent past', () {
      expect(Validators.transactionDate(DateTime.now()), isNull);
      expect(
        Validators.transactionDate(
          DateTime.now().subtract(const Duration(days: 400)),
        ),
        isNull,
      );
    });

    test('rejects a date far in the future, which is usually a misread year',
        () {
      expect(
        Validators.transactionDate(
          DateTime.now().add(const Duration(days: 500)),
        ),
        isNotNull,
      );
    });

    test('rejects an implausibly old date', () {
      expect(Validators.transactionDate(DateTime(1990)), isNotNull);
    });
  });

  group('Validators.dateRange', () {
    test('requires an ordered pair', () {
      final start = DateTime(2026, 9);
      expect(Validators.dateRange(start, DateTime(2026, 9, 30)), isNull);
      expect(Validators.dateRange(start, DateTime(2026, 8, 31)), isNotNull);
      expect(Validators.dateRange(null, DateTime(2026, 9, 30)), isNotNull);
    });
  });

  group('FileValidator', () {
    // Real magic numbers, since the validator checks the bytes rather than
    // trusting the extension.
    const jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0];
    const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    const pdf = [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37];
    const webp = [
      0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50,
    ];

    test('accepts supported image types', () {
      final jpegResult = FileValidator.validate(
        fileName: 'receipt.jpg',
        sizeBytes: 1024,
        headBytes: jpeg,
      );
      expect(jpegResult.mimeType, 'image/jpeg');
      expect(jpegResult.isImage, isTrue);

      expect(
        FileValidator.validate(
          fileName: 'scan.png',
          sizeBytes: 2048,
          headBytes: png,
        ).mimeType,
        'image/png',
      );

      expect(
        FileValidator.validate(
          fileName: 'photo.webp',
          sizeBytes: 2048,
          headBytes: webp,
        ).mimeType,
        'image/webp',
      );
    });

    test('accepts a PDF and flags it as one', () {
      final result = FileValidator.validate(
        fileName: 'statement.pdf',
        sizeBytes: 500000,
        headBytes: pdf,
      );
      expect(result.isPdf, isTrue);
      expect(result.mimeType, 'application/pdf');
    });

    test('rejects an unsupported extension', () {
      expect(
        () => FileValidator.validate(
          fileName: 'malware.exe',
          sizeBytes: 1024,
          headBytes: const [0x4D, 0x5A, 0, 0],
        ),
        throwsA(isA<FileException>()),
      );
    });

    test('rejects a file whose bytes contradict its extension', () {
      // An executable renamed to .pdf must not reach the OCR provider.
      expect(
        () => FileValidator.validate(
          fileName: 'statement.pdf',
          sizeBytes: 1024,
          headBytes: const [0x4D, 0x5A, 0x90, 0x00],
        ),
        throwsA(isA<FileException>()),
      );
    });

    test('rejects an empty file', () {
      expect(
        () => FileValidator.validate(
          fileName: 'empty.jpg',
          sizeBytes: 0,
          headBytes: jpeg,
        ),
        throwsA(isA<FileException>()),
      );
    });

    test('rejects a file over the configured limit', () {
      expect(
        () => FileValidator.validate(
          fileName: 'huge.pdf',
          sizeBytes: AppConfig.maxUploadBytes + 1,
          headBytes: pdf,
        ),
        throwsA(isA<FileException>()),
      );
    });

    test('rejects a file with no extension', () {
      expect(
        () => FileValidator.validate(
          fileName: 'receipt',
          sizeBytes: 1024,
          headBytes: jpeg,
        ),
        throwsA(isA<FileException>()),
      );
    });
  });
}
