import 'package:finora/core/ocr/parsing/parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parser tests.
///
/// These run without a camera, a model or a database: the parser takes text and
/// returns candidates, which is exactly why it is kept separate from the
/// recogniser. Every case below is a shape a real document produces.
///
/// Ported from the Cloud Functions' TypeScript when OCR moved on-device. The
/// assertions are the only thing that changed; not one expectation did — which is
/// what makes them evidence that the port is faithful rather than merely finished.
void main() {
  // ---------------------------------------------------------------------------
  // Amounts
  // ---------------------------------------------------------------------------

  group('parseAmountToken', () {
    test('reads grouped thousands with a decimal point', () {
      expect(parseAmountToken('8,450.00'), 8450);
      expect(parseAmountToken('1,234,567.89'), 1234567.89);
    });

    test('reads European grouping', () {
      expect(parseAmountToken('8.450,00'), 8450);
      expect(parseAmountToken('8450,50'), 8450.5);
    });

    test('strips currency symbols and codes', () {
      expect(parseAmountToken('Rs. 8,450.00'), 8450);
      expect(parseAmountToken('LKR 8450.00'), 8450);
      expect(parseAmountToken(r'$1,299.99'), 1299.99);
    });

    test('repairs the OCR letter-for-digit confusions', () {
      // A receipt printer's zero is routinely read as a capital O.
      expect(parseAmountToken('845O'), 8450);
      expect(parseAmountToken('1,2OO.50'), 1200.5);
      expect(parseAmountToken('l0.00'), 10);
    });

    test('treats brackets and minus as negative', () {
      expect(parseAmountToken('(1,500.00)'), -1500);
      expect(parseAmountToken('-250.75'), -250.75);
    });

    test('rejects text with no digits', () {
      expect(parseAmountToken('TOTAL'), isNull);
      expect(parseAmountToken(''), isNull);
    });

    test('rounds to cents', () {
      expect(parseAmountToken('10.005'), 10.01);
    });
  });

  group('selectAmount', () {
    test('prefers the labelled total over larger line items', () {
      final selection = selectAmount([
        'ABC SUPERMARKET',
        'Rice 5kg          2,450.00',
        'Cooking oil       9,800.00',
        'SUB TOTAL        12,250.00',
        'VAT 15%           1,837.50',
        'TOTAL LKR        14,087.50',
        'CASH             15,000.00',
        'CHANGE              912.50',
      ]);

      expect(selection.amount, isNotNull);
      expect(selection.amount!.value, 14087.5);
      expect(selection.confidence, greaterThan(0.8));
    });

    test('does not mistake the subtotal or the tax for the total', () {
      final selection = selectAmount([
        'CAFE KUMBUK',
        'SUB TOTAL   1,000.00',
        'SERVICE CHARGE 100.00',
        'TOTAL       1,100.00',
      ]);

      expect(selection.amount, isNotNull);
      expect(selection.amount!.value, 1100);
    });

    test('reports low confidence when nothing is labelled', () {
      final selection =
          selectAmount(['SOME SHOP', '2,500.00', '2,600.00']);

      expect(selection.amount, isNotNull);
      expect(
        selection.confidence,
        lessThan(0.8),
        reason: 'an unlabelled amount must be flagged for review',
      );
    });

    test('returns null rather than guessing when there is no amount', () {
      final selection = selectAmount(['THANK YOU', 'PLEASE CALL AGAIN']);
      expect(selection.amount, isNull);
      expect(selection.confidence, 0);
    });

    test('ignores a bare year that looks like a number', () {
      final selection = selectAmount(['RECEIPT', '2026', 'TOTAL 450.00']);
      expect(selection.amount, isNotNull);
      expect(selection.amount!.value, 450);
    });
  });

  // ---------------------------------------------------------------------------
  // Dates
  // ---------------------------------------------------------------------------

  // Pinned rather than relative, so these do not start failing in 2046.
  final dateOptions = DateParseOptions(
    notAfter: DateTime.utc(2030, 1, 1),
    notBefore: DateTime.utc(2010, 1, 1),
  );

  group('parseDateToken', () {
    test('deduces day-first when the day exceeds 12', () {
      final parsed = parseDateToken('15/09/2026', dateOptions);
      expect(parsed?.iso, '2026-09-15');
      expect(parsed?.ambiguous, isFalse);
    });

    test('deduces month-first when the second part exceeds 12', () {
      final parsed = parseDateToken('09/15/2026', dateOptions);
      expect(parsed?.iso, '2026-09-15');
      expect(parsed?.ambiguous, isFalse);
    });

    test('flags a genuinely ambiguous date with low confidence', () {
      final parsed = parseDateToken('03/04/2026', dateOptions);
      expect(parsed?.iso, '2026-04-03');
      expect(parsed?.ambiguous, isTrue);
      expect(
        parsed!.confidence,
        lessThan(0.8),
        reason: 'an ambiguous date must fall below the review threshold',
      );
    });

    test('honours an explicit month-first preference', () {
      final parsed = parseDateToken(
        '03/04/2026',
        DateParseOptions(
          preferDayFirst: false,
          notAfter: dateOptions.notAfter,
          notBefore: dateOptions.notBefore,
        ),
      );
      expect(parsed?.iso, '2026-03-04');
      expect(parsed?.ambiguous, isTrue);
    });

    test('reads a four-digit leading year', () {
      expect(parseDateToken('2026-09-15', dateOptions)?.iso, '2026-09-15');
    });

    test('reads written month names in both orders', () {
      expect(parseDateToken('15 Sep 2026', dateOptions)?.iso, '2026-09-15');
      expect(
        parseDateToken('15th September 2026', dateOptions)?.iso,
        '2026-09-15',
      );
      expect(parseDateToken('Sep 15, 2026', dateOptions)?.iso, '2026-09-15');
    });

    test('expands a two-digit year into this century', () {
      expect(parseDateToken('15/09/26', dateOptions)?.iso, '2026-09-15');
    });

    test('rejects a date the calendar does not have', () {
      expect(parseDateToken('31/02/2026', dateOptions), isNull);
      expect(parseDateToken('32/01/2026', dateOptions), isNull);
    });

    test('rejects dates outside the plausible window', () {
      expect(parseDateToken('15/09/2045', dateOptions), isNull);
      expect(parseDateToken('15/09/1998', dateOptions), isNull);
    });
  });

  test('selectDate prefers a transaction date over a due date', () {
    final selected = selectDate([
      'TAX INVOICE',
      'Invoice Date: 15/09/2026',
      'Due Date: 30/09/2026',
    ], dateOptions);

    expect(selected?.iso, '2026-09-15');
  });

  // ---------------------------------------------------------------------------
  // Classification and field extraction
  // ---------------------------------------------------------------------------

  test('classifyDocument recognises a bank statement from its columns', () {
    final text = [
      'COMMERCIAL BANK OF CEYLON PLC',
      'STATEMENT OF ACCOUNT',
      'Statement Period: 01/09/2026 to 30/09/2026',
      'Date        Description        Debit      Credit     Balance',
      'OPENING BALANCE                                    250,000.00',
      '15/09/26    ABC SUPERMARKET    8,450.00            241,550.00',
    ].join('\n');

    expect(classifyDocument(text).kind, 'BANK_STATEMENT');
  });

  test('classifyDocument recognises an invoice', () {
    final text = [
      'TAX INVOICE',
      'Invoice No: INV-2026-0091',
      'Bill To: Pasindu',
      'Due Date: 30/09/2026',
      'Total Payable 45,000.00',
    ].join('\n');

    expect(classifyDocument(text).kind, 'INVOICE');
  });

  test('normaliseMerchant title-cases shouty receipt headers', () {
    expect(
      normaliseMerchant('ABC  SUPERMARKET (PVT) LTD'),
      'ABC Supermarket (Pvt) LTD',
    );
    // Already mixed case: left exactly as the merchant writes it.
    expect(normaliseMerchant('Cafe Kumbuk'), 'Cafe Kumbuk');
  });

  test('extractPaymentMethod maps card brands to a card method', () {
    expect(extractPaymentMethod('PAID BY VISA ****1234').method, 'CREDIT_CARD');
    expect(extractPaymentMethod('CASH TENDERED 500').method, 'CASH');
  });

  test('extractReference finds a transaction reference and skips short digits',
      () {
    expect(
      extractReference('Transaction Ref: TXN20260915AB').reference,
      'TXN20260915AB',
    );
    expect(extractReference('Ref: 12').reference, isNull);
  });

  test('suggestCategoryName maps a known merchant to a default category', () {
    expect(suggestCategoryName('KEELLS SUPER').name, 'Groceries');
    expect(suggestCategoryName('PICKME PVT LTD').name, 'Transport');
    expect(suggestCategoryName('CEB ELECTRICITY BILL').name, 'Utilities');
    expect(suggestCategoryName('something unrecognised').name, isNull);
  });

  // ---------------------------------------------------------------------------
  // End-to-end: receipt
  // ---------------------------------------------------------------------------

  const options = ParseOptions(defaultCurrency: 'LKR');

  test('parseDocument turns a receipt into one reviewable candidate', () {
    final text = [
      'ABC SUPERMARKET',
      'No 42, Galle Road, Colombo 03',
      'Tel: 0112345678',
      'Bill No: 998877',
      '15/09/2026 14:32',
      'Groceries',
      'Rice 5kg        2,450.00',
      'SUB TOTAL       8,450.00',
      'TOTAL LKR       8,450.00',
      'VISA ****1234',
      'THANK YOU',
    ].join('\n');

    final result = parseDocument(text, options);

    expect(result.candidates.length, 1);
    final candidate = result.candidates.first;

    expect(candidate.amount, 8450);
    expect(candidate.currency, 'LKR');
    expect(candidate.transactionDate, '2026-09-15');
    expect(candidate.transactionType, 'EXPENSE');
    expect(candidate.paymentMethod, 'CREDIT_CARD');
    expect(candidate.suggestedCategoryName, 'Groceries');
    expect(candidate.merchant?.toLowerCase(), contains('supermarket'));
  });

  test('parseDocument marks a receipt as income when the text says so', () {
    final text = [
      'PAYMENT RECEIPT',
      'Salary credited to your account',
      'Date: 25/09/2026',
      'Amount LKR 250,000.00',
    ].join('\n');

    final result = parseDocument(text, options);
    expect(result.candidates.first.transactionType, 'INCOME');
  });

  test('parseDocument yields no candidate from a document with nothing in it',
      () {
    final result =
        parseDocument('THANK YOU\nPLEASE COME AGAIN', options);
    expect(result.candidates, isEmpty);
  });

  test('parseDocument leaves the amount null when none can be found', () {
    // A merchant and a date but no total: the candidate exists so the user can
    // finish it, with the amount blank rather than fabricated.
    final result = parseDocument(
      ['KEELLS SUPER', 'Date: 15/09/2026', 'Thank you'].join('\n'),
      options,
    );

    expect(result.candidates.length, 1);
    expect(result.candidates.first.amount, isNull);
    expect(
      result.candidates.first.fieldConfidence.containsKey('amount'),
      isFalse,
      reason: 'a missing field must carry no confidence score at all',
    );
  });

  // ---------------------------------------------------------------------------
  // End-to-end: bank statement
  // ---------------------------------------------------------------------------

  final statement = [
    'COMMERCIAL BANK OF CEYLON PLC',
    'STATEMENT OF ACCOUNT',
    'Account No: ****4321',
    'Statement Period: 01/09/2026 to 30/09/2026',
    'Date      Description              Debit       Credit      Balance',
    'OPENING BALANCE                                          250,000.00',
    '15/09/26  POS ABC SUPERMARKET      8,450.00              241,550.00',
    '16/09/26  SALARY CREDIT SEP                  250,000.00  491,550.00',
    '17/09/26  POS PICKME PVT LTD       1,800.00              489,750.00',
    'CLOSING BALANCE                                          489,750.00',
  ].join('\n');

  test('parseDocument extracts one candidate per statement row', () {
    final result = parseDocument(statement, options);

    expect(result.documentKind, 'BANK_STATEMENT');
    expect(result.candidates.length, 3);

    final supermarket = result.candidates[0];
    final salary = result.candidates[1];
    final ride = result.candidates[2];

    expect(supermarket.amount, 8450);
    expect(supermarket.transactionDate, '2026-09-15');
    expect(supermarket.transactionType, 'EXPENSE');

    expect(salary.amount, 250000);
    expect(salary.transactionType, 'INCOME');

    expect(ride.amount, 1800);
    expect(ride.transactionType, 'EXPENSE');
  });

  test('statement parsing excludes the running balance column', () {
    final result = parseDocument(statement, options);
    final amounts = result.candidates.map((c) => c.amount).toList();

    // 241,550.00 and 489,750.00 are balances, not transactions.
    expect(amounts, isNot(contains(241550)));
    expect(amounts, isNot(contains(489750)));
  });

  test('statement parsing skips opening and closing balance rows', () {
    final result = parseDocument(statement, options);
    expect(result.candidates.length, 3);
    for (final candidate in result.candidates) {
      expect(
        RegExp('balance', caseSensitive: false)
            .hasMatch(candidate.description ?? ''),
        isFalse,
      );
    }
  });

  test('statement parsing honours explicit Dr and Cr markers', () {
    final text = [
      'ACCOUNT STATEMENT',
      'Statement Period: 01/09/2026 to 30/09/2026',
      'Opening Balance 10,000.00',
      '15/09/26  CARD PAYMENT     2,500.00 DR',
      '16/09/26  REFUND RECEIVED  1,200.00 CR',
    ].join('\n');

    final result = parseDocument(text, options);
    final byAmount = {
      for (final c in result.candidates) c.amount: c,
    };

    expect(byAmount[2500]?.transactionType, 'EXPENSE');
    expect(byAmount[1200]?.transactionType, 'INCOME');
  });

  test('every candidate carries a confidence for each populated field', () {
    final result = parseDocument(statement, options);

    for (final candidate in result.candidates) {
      expect(candidate.confidence, isNotNull);
      expect(candidate.confidence, greaterThan(0));
      expect(candidate.confidence, lessThanOrEqualTo(1));
      expect(candidate.fieldConfidence.containsKey('amount'), isTrue);
      expect(candidate.fieldConfidence.containsKey('date'), isTrue);

      for (final score in candidate.fieldConfidence.values) {
        expect(score, inInclusiveRange(0, 1));
      }
    }
  });

  test('candidate confidence is the mean of its field scores', () {
    final result = parseDocument(statement, options);
    final candidate = result.candidates.first;
    final scores = candidate.fieldConfidence.values.toList();
    final expected = scores.reduce((a, b) => a + b) / scores.length;

    expect(candidate.confidence, closeTo(expected, 0.001));
  });
}
