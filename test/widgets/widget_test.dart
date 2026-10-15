import 'dart:io';

import 'package:finora/core/constants/enums.dart';
import 'package:finora/core/theme/app_colors.dart';
import 'package:finora/core/theme/app_theme.dart';
import 'package:finora/core/utils/money.dart';
import 'package:finora/shared/models/account.dart';
import 'package:finora/shared/models/budget.dart';
import 'package:finora/shared/models/category.dart';
import 'package:finora/shared/models/transaction.dart';
import 'package:finora/shared/models/transaction_candidate.dart';
import 'package:finora/shared/widgets/form_fields.dart';
import 'package:finora/shared/widgets/money_text.dart';
import 'package:finora/shared/widgets/state_views.dart';
import 'package:finora/shared/widgets/transaction_tile.dart';
import 'package:finora/core/utils/app_date_utils.dart';
import 'package:finora/features/ocr/presentation/widgets/confidence_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the pieces whose rendering carries meaning: amounts, their
/// colours and signs, the confidence badges on the OCR review screen, and the
/// empty and error states.
void main() {
  /// Wraps a widget in the real app theme, so colour assertions test what a user
  /// would actually see rather than Flutter's defaults.
  Widget host(Widget child, {Brightness brightness = Brightness.light}) {
    return MaterialApp(
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      home: Scaffold(body: Center(child: child)),
    );
  }

  Transaction transaction({
    TransactionType type = TransactionType.expense,
    double amount = 1250,
    String? merchant = 'Cafe Kumbuk',
    String? description,
    TransactionStatus status = TransactionStatus.confirmed,
    TransactionSource source = TransactionSource.manual,
    String? documentId,
    Category? category,
    Account? account,
  }) {
    return Transaction(
      id: 'txn-1',
      userId: 'user-1',
      accountId: 'acc-1',
      type: type,
      amount: Money.fromMajor(amount),
      merchant: merchant,
      description: description,
      transactionDate: DateTime(2026, 9, 15, 13, 45),
      status: status,
      source: source,
      documentId: documentId,
      category: category,
      account: account,
      createdAt: DateTime(2026, 9, 15),
      updatedAt: DateTime(2026, 9, 15),
    );
  }

  group('MoneyText', () {
    testWidgets('formats an amount with symbol and grouping', (tester) async {
      await tester.pumpWidget(host(MoneyText(Money.fromMajor(8450))));
      expect(find.text('Rs. 8,450.00'), findsOneWidget);
    });

    testWidgets('an expense is signed negative and coloured', (tester) async {
      await tester.pumpWidget(
        host(
          MoneyText.transaction(
            Money.fromMajor(1250),
            transactionType: TransactionType.expense,
          ),
        ),
      );

      expect(find.text('-Rs. 1,250.00'), findsOneWidget);
      // Colour carries meaning here, so it is asserted rather than assumed.
      final text = tester.widget<Text>(find.text('-Rs. 1,250.00'));
      expect(text.style?.color, AppPalette.light.expense);
    });

    testWidgets('income is signed positive', (tester) async {
      await tester.pumpWidget(
        host(
          MoneyText.transaction(
            Money.fromMajor(250000),
            transactionType: TransactionType.income,
          ),
        ),
      );
      expect(find.text('+Rs. 250,000.00'), findsOneWidget);
    });

    testWidgets('a transfer is unsigned, being neither gain nor loss',
        (tester) async {
      await tester.pumpWidget(
        host(
          MoneyText.transaction(
            Money.fromMajor(20000),
            transactionType: TransactionType.transfer,
          ),
        ),
      );
      expect(find.text('Rs. 20,000.00'), findsOneWidget);
    });

    testWidgets('obscured amounts hide the figure entirely', (tester) async {
      await tester.pumpWidget(
        host(MoneyText(Money.fromMajor(250000), obscured: true)),
      );
      expect(find.text('****'), findsOneWidget);
      expect(find.textContaining('250'), findsNothing);
    });

    testWidgets('compact form is used for large figures', (tester) async {
      await tester.pumpWidget(
        host(MoneyText(Money.fromMajor(1250000), compact: true)),
      );
      expect(find.text('Rs. 1.3M'), findsOneWidget);
    });
  });

  group('TransactionTile', () {
    testWidgets('shows the merchant, time and amount', (tester) async {
      await tester.pumpWidget(host(
        TransactionTile(transaction: transaction()),
      ));

      expect(find.text('Cafe Kumbuk'), findsOneWidget);
      expect(find.textContaining('1:45 PM'), findsOneWidget);
      expect(find.text('-Rs. 1,250.00'), findsOneWidget);
    });

    testWidgets('falls back to the description when there is no merchant',
        (tester) async {
      await tester.pumpWidget(host(
        TransactionTile(
          transaction: transaction(merchant: null, description: 'Bus fare'),
        ),
      ));
      expect(find.text('Bus fare'), findsOneWidget);
    });

    testWidgets('marks a pending draft, so a user knows why the balance has not '
        'moved', (tester) async {
      await tester.pumpWidget(host(
        TransactionTile(
          transaction: transaction(status: TransactionStatus.pending),
        ),
      ));
      expect(find.text('Pending'), findsOneWidget);
    });

    testWidgets('shows an attachment indicator', (tester) async {
      await tester.pumpWidget(host(
        TransactionTile(
          transaction: transaction(
            documentId: 'doc-1',
            source: TransactionSource.ocrImage,
          ),
        ),
      ));

      expect(find.byIcon(Icons.attach_file_rounded), findsOneWidget);
      expect(find.byIcon(Icons.document_scanner_outlined), findsOneWidget);
    });

    testWidgets('calls onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(host(
        TransactionTile(
          transaction: transaction(),
          onTap: () => tapped = true,
        ),
      ));

      await tester.tap(find.byType(TransactionTile));
      expect(tapped, isTrue);
    });
  });

  group('TransactionDayHeader', () {
    testWidgets('labels today and shows the day net', (tester) async {
      final group = TransactionDayGroup(
        date: AppDateUtils.startOfDay(DateTime.now()),
        transactions: [
          transaction(amount: 1000),
          transaction(type: TransactionType.income, amount: 2500),
        ],
      );

      await tester.pumpWidget(host(
        TransactionDayHeader(group: group, currency: 'LKR'),
      ));

      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('Rs. 1,500.00'), findsOneWidget);
    });
  });

  group('EmptyState', () {
    testWidgets('shows the message and triggers its action', (tester) async {
      var pressed = false;
      await tester.pumpWidget(host(
        EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'No transactions yet',
          message: 'Start tracking your finances by adding your first '
              'transaction.',
          actionLabel: 'Add transaction',
          onAction: () => pressed = true,
        ),
      ));

      expect(find.text('No transactions yet'), findsOneWidget);
      expect(
        find.textContaining('Start tracking your finances'),
        findsOneWidget,
      );

      await tester.tap(find.text('Add transaction'));
      expect(pressed, isTrue);
    });
  });

  group('ErrorStateView', () {
    testWidgets('maps an exception to a readable message', (tester) async {
      await tester.pumpWidget(host(
        const ErrorStateView(error: SocketException('no route to host')),
      ));

      // The user sees guidance, never the exception type.
      expect(find.textContaining('connection'), findsWidgets);
      expect(find.textContaining('SocketException'), findsNothing);
    });

    testWidgets('offers a retry when one is given', (tester) async {
      var retried = false;
      await tester.pumpWidget(host(
        ErrorStateView(
          error: Exception('boom'),
          onRetry: () => retried = true,
        ),
      ));

      await tester.tap(find.text('Try again'));
      expect(retried, isTrue);
    });

    testWidgets('never shows a raw exception string', (tester) async {
      await tester.pumpWidget(host(
        ErrorStateView(error: Exception('PostgrestException: 42501 denied')),
      ));

      expect(find.textContaining('42501'), findsNothing);
      expect(find.textContaining('Postgrest'), findsNothing);
      expect(find.text('Something went wrong'), findsOneWidget);
    });
  });

  group('ProgressMeter', () {
    testWidgets('renders within its bounds when overfilled', (tester) async {
      await tester.pumpWidget(host(
        const SizedBox(
          width: 200,
          child: ProgressMeter(
            fraction: 1.4,
            color: Colors.red,
            showOverflow: true,
          ),
        ),
      ));

      expect(tester.takeException(), isNull);
    });
  });

  group('AmountField', () {
    testWidgets('shows the currency symbol as a prefix', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(
        SizedBox(
          width: 300,
          child: AmountField(controller: controller, currency: 'LKR'),
        ),
      ));

      expect(find.text('Rs.'), findsOneWidget);
    });

    testWidgets('rejects letters and accepts digits', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(
        SizedBox(
          width: 300,
          child: AmountField(controller: controller, currency: 'LKR'),
        ),
      ));

      await tester.enterText(find.byType(TextFormField), 'abc');
      expect(controller.text, isEmpty);

      await tester.enterText(find.byType(TextFormField), '1250.50');
      expect(controller.text, '1250.50');
    });

    testWidgets('caps the decimal places at the currency scale', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(
        SizedBox(
          width: 300,
          child: AmountField(controller: controller, currency: 'LKR'),
        ),
      ));

      await tester.enterText(find.byType(TextFormField), '10.5');
      await tester.enterText(find.byType(TextFormField), '10.555');
      // The third decimal is refused, so the value always fits numeric(16,2).
      expect(controller.text, '10.5');
    });

    testWidgets('refuses a negative unless explicitly allowed', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(
        SizedBox(
          width: 300,
          child: AmountField(controller: controller, currency: 'LKR'),
        ),
      ));

      await tester.enterText(find.byType(TextFormField), '-100');
      expect(controller.text, isEmpty);
    });

    testWidgets('allocates width for editable text region', (tester) async {
      final controller = TextEditingController(text: '100');
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(
        SizedBox(
          width: 300,
          child: AmountField(controller: controller, currency: 'LKR'),
        ),
      ));

      final editableTextSize = tester.getSize(find.byType(EditableText));
      expect(editableTextSize.width, greaterThan(100));
    });
  });

  group('SegmentedTypeSelector', () {
    testWidgets('reports the selected option', (tester) async {
      TransactionType? selected;

      await tester.pumpWidget(host(
        SizedBox(
          width: 360,
          child: SegmentedTypeSelector<TransactionType>(
            options: TransactionType.values,
            selected: TransactionType.expense,
            labelFor: (t) => t.label,
            onChanged: (t) => selected = t,
          ),
        ),
      ));

      expect(find.text('Expense'), findsOneWidget);
      expect(find.text('Income'), findsOneWidget);
      expect(find.text('Transfer'), findsOneWidget);

      await tester.tap(find.text('Income'));
      expect(selected, TransactionType.income);
    });
  });

  group('ConfidenceBadge', () {
    testWidgets('a high score reads as confident', (tester) async {
      await tester.pumpWidget(host(
        const ConfidenceBadge(level: ConfidenceLevel.high, score: 0.99),
      ));
      expect(find.textContaining('High confidence'), findsOneWidget);
      expect(find.textContaining('99%'), findsOneWidget);
    });

    testWidgets('a low score asks the user to verify', (tester) async {
      await tester.pumpWidget(host(
        const ConfidenceBadge(level: ConfidenceLevel.low, score: 0.72),
      ));
      expect(find.textContaining('Please verify'), findsOneWidget);
      expect(find.textContaining('72%'), findsOneWidget);
    });

    testWidgets('a missing field says so without a percentage', (tester) async {
      await tester.pumpWidget(host(
        const ConfidenceBadge(level: ConfidenceLevel.missing),
      ));
      expect(find.text('Not detected'), findsOneWidget);
    });
  });

  group('confidenceLevelFor', () {
    test('absent values are missing, scoreless values are unverified', () {
      expect(
        confidenceLevelFor(null, hasValue: false),
        ConfidenceLevel.missing,
      );
      // Present but unscored must not read as confident.
      expect(confidenceLevelFor(null, hasValue: true), ConfidenceLevel.low);
      expect(confidenceLevelFor(0.99, hasValue: true), ConfidenceLevel.high);
      expect(confidenceLevelFor(0.85, hasValue: true), ConfidenceLevel.medium);
      expect(confidenceLevelFor(0.62, hasValue: true), ConfidenceLevel.low);
    });
  });

  group('CandidateWarnings', () {
    testWidgets('an empty list reads as ready to confirm', (tester) async {
      await tester.pumpWidget(host(
        const SizedBox(width: 360, child: CandidateWarnings(warnings: [])),
      ));
      expect(find.textContaining('looks readable'), findsOneWidget);
    });

    testWidgets('blocking warnings are stated first and plainly',
        (tester) async {
      await tester.pumpWidget(host(
        const SizedBox(
          width: 360,
          child: CandidateWarnings(
            warnings: [
              CandidateWarning(
                CandidateField.category,
                'Category not suggested',
                'Choose a category.',
              ),
              CandidateWarning(
                CandidateField.amount,
                'Amount not detected',
                'Enter the transaction amount.',
                blocking: true,
              ),
            ],
          ),
        ),
      ));

      expect(find.textContaining('needed before saving'), findsOneWidget);
      expect(find.text('Amount not detected'), findsOneWidget);
      expect(find.text('Category not suggested'), findsOneWidget);
    });
  });

  group('SplitMismatchBanner', () {
    testWidgets('states the shortfall', (tester) async {
      await tester.pumpWidget(host(
        SizedBox(
          width: 360,
          child: SplitMismatchBanner(
            total: Money.fromMajor(10000),
            splitTotal: Money.fromMajor(8500),
          ),
        ),
      ));

      expect(find.textContaining('Rs. 1,500.00'), findsOneWidget);
      expect(find.textContaining('under'), findsOneWidget);
    });
  });

  group('Dark theme', () {
    testWidgets('amounts stay legible in dark mode', (tester) async {
      await tester.pumpWidget(host(
        MoneyText.transaction(
          Money.fromMajor(1250),
          transactionType: TransactionType.expense,
        ),
        brightness: Brightness.dark,
      ));

      expect(find.text('-Rs. 1,250.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a budget row renders in both themes', (tester) async {
      final progress = BudgetProgress(
        budget: Budget(
          id: 'b-1',
          userId: 'u-1',
          name: 'Food',
          amount: Money.fromMajor(30000),
          period: BudgetPeriod.monthly,
          startDate: DateTime(2026, 9),
          createdAt: DateTime(2026, 9),
          updatedAt: DateTime(2026, 9),
        ),
        spent: Money.fromMajor(22500),
        range: DateRange(DateTime(2026, 9), DateTime(2026, 9, 30)),
      );

      for (final brightness in Brightness.values) {
        await tester.pumpWidget(host(
          SizedBox(
            width: 360,
            child: ProgressMeter(
              fraction: progress.progressFraction,
              color: Colors.green,
            ),
          ),
          brightness: brightness,
        ));
        expect(tester.takeException(), isNull);
      }
    });
  });
}
