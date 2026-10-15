import 'package:finora/core/constants/enums.dart';
import 'package:finora/core/utils/app_date_utils.dart';
import 'package:finora/core/utils/money.dart';
import 'package:finora/shared/models/account.dart';
import 'package:finora/shared/models/analytics.dart';
import 'package:finora/shared/models/bill.dart';
import 'package:finora/shared/models/budget.dart';
import 'package:finora/shared/models/calculations.dart';
import 'package:finora/shared/models/savings_goal.dart';
import 'package:finora/shared/models/subscription.dart';
import 'package:finora/shared/models/transaction.dart';
import 'package:finora/shared/models/transaction_candidate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the financial arithmetic the UI depends on.
///
/// These are the calculations a user would notice being wrong: balances,
/// savings rates, budget progress, goal projections and subscription costs.
void main() {
  // --- Builders -------------------------------------------------------------

  Account account({
    String id = 'acc-1',
    AccountType type = AccountType.bank,
    double balance = 0,
    double initial = 0,
    String currency = 'LKR',
    double? creditLimit,
    bool isActive = true,
    bool isArchived = false,
  }) {
    return Account(
      id: id,
      userId: 'user-1',
      name: 'Account $id',
      type: type,
      currency: currency,
      initialBalance: Money.fromMajor(initial, currency),
      currentBalance: Money.fromMajor(balance, currency),
      creditLimit:
          creditLimit == null ? null : Money.fromMajor(creditLimit, currency),
      isActive: isActive,
      isArchived: isArchived,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
  }

  Transaction transaction({
    String id = 'txn-1',
    TransactionType type = TransactionType.expense,
    double amount = 100,
    DateTime? date,
    TransferDirection? direction,
    TransactionStatus status = TransactionStatus.confirmed,
    String? merchant,
  }) {
    return Transaction(
      id: id,
      userId: 'user-1',
      accountId: 'acc-1',
      type: type,
      amount: Money.fromMajor(amount),
      transactionDate: date ?? DateTime(2026, 9, 15),
      transferDirection: direction,
      transferGroupId: direction == null ? null : 'group-1',
      status: status,
      merchant: merchant,
      createdAt: DateTime(2026, 9, 15),
      updatedAt: DateTime(2026, 9, 15),
    );
  }

  // --- Signed amounts -------------------------------------------------------

  group('Transaction.signedAmount', () {
    test('income is positive and expense negative', () {
      expect(
        transaction(type: TransactionType.income, amount: 250).signedAmount,
        Money.fromMajor(250),
      );
      expect(
        transaction(type: TransactionType.expense, amount: 250).signedAmount,
        Money.fromMajor(-250),
      );
    });

    test('a transfer out is negative and a transfer in positive', () {
      expect(
        transaction(
          type: TransactionType.transfer,
          amount: 20000,
          direction: TransferDirection.out,
        ).signedAmount,
        Money.fromMajor(-20000),
      );
      expect(
        transaction(
          type: TransactionType.transfer,
          amount: 20000,
          direction: TransferDirection.incoming,
        ).signedAmount,
        Money.fromMajor(20000),
      );
    });

    test('the two legs of a transfer cancel out', () {
      // The defining property: a transfer moves money without changing the
      // total across accounts.
      final out = transaction(
        type: TransactionType.transfer,
        amount: 20000,
        direction: TransferDirection.out,
      );
      final incoming = transaction(
        id: 'txn-2',
        type: TransactionType.transfer,
        amount: 20000,
        direction: TransferDirection.incoming,
      );
      expect(out.signedAmount + incoming.signedAmount, Money.zero());
    });

    test('a transfer is excluded from income and expense counts', () {
      final transfer = transaction(
        type: TransactionType.transfer,
        amount: 100,
        direction: TransferDirection.out,
      );
      expect(transfer.countsAsIncome, isFalse);
      expect(transfer.countsAsExpense, isFalse);
      expect(transfer.type.affectsCashflow, isFalse);
    });

    test('a pending draft does not count towards cashflow', () {
      final draft = transaction(status: TransactionStatus.pending);
      expect(draft.countsAsExpense, isFalse);
      expect(draft.isPending, isTrue);
    });
  });

  // --- Account totals -------------------------------------------------------

  group('AccountRepository.totalBalance', () {
    test('sums active accounts in the display currency', () {
      final result = AccountTotals.balance([
        account(id: 'a', balance: 250000),
        account(id: 'b', balance: 15000),
        account(id: 'c', balance: 8500),
      ], 'LKR');

      expect(result.total, Money.fromMajor(273500));
      expect(result.excludedCount, 0);
    });

    test('excludes archived and inactive accounts', () {
      final result = AccountTotals.balance([
        account(id: 'a', balance: 100),
        account(id: 'b', balance: 999, isArchived: true),
        account(id: 'c', balance: 999, isActive: false),
      ], 'LKR');

      expect(result.total, Money.fromMajor(100));
    });

    test('skips other currencies and reports how many', () {
      // Converting at an invented rate would produce a confidently wrong total,
      // so those accounts are left out and counted instead.
      final result = AccountTotals.balance([
        account(id: 'a', balance: 100000),
        account(id: 'b', balance: 500, currency: 'USD'),
        account(id: 'c', balance: 300, currency: 'EUR'),
      ], 'LKR');

      expect(result.total, Money.fromMajor(100000));
      expect(result.excludedCount, 2);
    });

    test('an empty list totals zero', () {
      expect(
        AccountTotals.balance(const [], 'LKR').total,
        Money.zero(),
      );
    });
  });

  group('Account credit cards', () {
    test('available credit accounts for the debt already held', () {
      // A card balance is negative when money is owed.
      final card = account(
        type: AccountType.creditCard,
        balance: -42000,
        creditLimit: 300000,
      );
      expect(card.availableCredit, Money.fromMajor(258000));
      expect(card.creditUtilisation, closeTo(14, 0.5));
    });

    test('no credit figures on a non-card account', () {
      final bank = account(balance: 1000);
      expect(bank.availableCredit, isNull);
      expect(bank.creditUtilisation, isNull);
    });

    test('a zero limit does not divide by zero', () {
      final card = account(
        type: AccountType.creditCard,
        balance: -100,
        creditLimit: 0,
      );
      expect(card.creditUtilisation, isNull);
    });
  });

  // --- Cashflow -------------------------------------------------------------

  group('CashflowSummary', () {
    final range = DateRange(DateTime(2026, 9), DateTime(2026, 9, 30));

    test('savings is income minus expenses', () {
      final summary = CashflowSummary(
        range: range,
        income: Money.fromMajor(285000),
        expenses: Money.fromMajor(187500),
      );
      expect(summary.savings, Money.fromMajor(97500));
      expect(summary.isOverspending, isFalse);
    });

    test('savings rate is a percentage of income', () {
      final summary = CashflowSummary(
        range: range,
        income: Money.fromMajor(100000),
        expenses: Money.fromMajor(75000),
      );
      expect(summary.savingsRate, closeTo(25, 0.0001));
    });

    test('a month with no income has a zero rate, not infinity', () {
      final summary = CashflowSummary(
        range: range,
        income: Money.zero(),
        expenses: Money.fromMajor(5000),
      );
      expect(summary.savingsRate, 0);
      expect(summary.isOverspending, isTrue);
    });

    test('overspending gives a negative savings figure', () {
      final summary = CashflowSummary(
        range: range,
        income: Money.fromMajor(50000),
        expenses: Money.fromMajor(70000),
      );
      expect(summary.savings, Money.fromMajor(-20000));
      expect(summary.savingsRate, closeTo(-40, 0.0001));
    });

    test('average daily spend divides by the period length', () {
      final summary = CashflowSummary(
        range: DateRange(DateTime(2026, 9), DateTime(2026, 9, 30)),
        income: Money.fromMajor(0),
        expenses: Money.fromMajor(30000),
      );
      expect(summary.averageDailySpend, Money.fromMajor(1000));
    });

    test('change percent is null when there is nothing to compare', () {
      expect(
        CashflowSummary.changePercent(Money.fromMajor(100), Money.zero()),
        isNull,
      );
      expect(
        CashflowSummary.changePercent(
          Money.fromMajor(150),
          Money.fromMajor(100),
        ),
        closeTo(50, 0.0001),
      );
      expect(
        CashflowSummary.changePercent(
          Money.fromMajor(50),
          Money.fromMajor(100),
        ),
        closeTo(-50, 0.0001),
      );
    });
  });

  // --- Budgets --------------------------------------------------------------

  group('BudgetProgress', () {
    Budget budget({double amount = 30000, int threshold = 80}) => Budget(
          id: 'b-1',
          userId: 'user-1',
          categoryId: 'cat-1',
          name: 'Food',
          amount: Money.fromMajor(amount),
          period: BudgetPeriod.monthly,
          startDate: DateTime(2026, 9),
          alertThreshold: threshold,
          createdAt: DateTime(2026, 9),
          updatedAt: DateTime(2026, 9),
        );

    final range = DateRange(
      DateTime(2026, 9),
      DateTime(2026, 9, 30, 23, 59, 59, 999),
    );

    test('remaining and percentage for a partly spent budget', () {
      final progress = BudgetProgress(
        budget: budget(),
        spent: Money.fromMajor(22500),
        range: range,
      );

      expect(progress.remaining, Money.fromMajor(7500));
      expect(progress.percentUsed, closeTo(75, 0.0001));
      expect(progress.isExceeded, isFalse);
      expect(progress.overspend, Money.zero());
    });

    test('remaining never goes negative; overspend reports it instead', () {
      final progress = BudgetProgress(
        budget: budget(),
        spent: Money.fromMajor(35000),
        range: range,
      );

      expect(progress.remaining, Money.zero());
      expect(progress.overspend, Money.fromMajor(5000));
      expect(progress.isExceeded, isTrue);
      expect(progress.percentUsed, closeTo(116.67, 0.01));
    });

    test('progress fraction is clamped for the bar', () {
      final progress = BudgetProgress(
        budget: budget(),
        spent: Money.fromMajor(60000),
        range: range,
      );
      expect(progress.progressFraction, 1.0);
    });

    test('health reflects the threshold and the limit', () {
      expect(
        BudgetProgress(
          budget: budget(),
          spent: Money.fromMajor(10000),
          range: range,
        ).health,
        BudgetHealth.healthy,
      );
      expect(
        BudgetProgress(
          budget: budget(),
          spent: Money.fromMajor(25000),
          range: range,
        ).health,
        BudgetHealth.warning,
      );
      expect(
        BudgetProgress(
          budget: budget(),
          spent: Money.fromMajor(28000),
          range: range,
        ).health,
        BudgetHealth.critical,
      );
      expect(
        BudgetProgress(
          budget: budget(),
          spent: Money.fromMajor(31000),
          range: range,
        ).health,
        BudgetHealth.exceeded,
      );
    });

    test('a zero-spend budget is at zero percent, not an error', () {
      final progress = BudgetProgress(
        budget: budget(),
        spent: Money.zero(),
        range: range,
      );
      expect(progress.percentUsed, 0);
      expect(progress.remaining, Money.fromMajor(30000));
    });

    test('a repeating budget resolves to the period containing the date', () {
      // Created in January but evaluated in September: the window must be
      // September, otherwise the figures describe the wrong month.
      final january = Budget(
        id: 'b-2',
        userId: 'user-1',
        amount: Money.fromMajor(50000),
        period: BudgetPeriod.monthly,
        startDate: DateTime(2026),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      final resolved = january.currentRange(DateTime(2026, 9, 15));
      expect(resolved.start, DateTime(2026, 9));
      expect(resolved.end.month, 9);
    });
  });

  // --- Savings goals --------------------------------------------------------

  group('SavingsGoal', () {
    SavingsGoal goal({
      double target = 300000,
      double current = 125000,
      DateTime? targetDate,
    }) =>
        SavingsGoal(
          id: 'g-1',
          userId: 'user-1',
          name: 'New Laptop',
          targetAmount: Money.fromMajor(target),
          currentAmount: Money.fromMajor(current),
          targetDate: targetDate,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    test('progress percentage and remaining', () {
      final g = goal();
      expect(g.progressPercent, closeTo(41.67, 0.01));
      expect(g.remaining, Money.fromMajor(175000));
      expect(g.isReached, isFalse);
    });

    test('an over-funded goal clamps at 100 percent', () {
      final g = goal(target: 100000, current: 120000);
      expect(g.progressPercent, 100);
      expect(g.remaining, Money.zero());
      expect(g.isReached, isTrue);
    });

    test('required monthly contribution spreads the shortfall', () {
      final g = goal(
        target: 300000,
        current: 0,
        targetDate: DateTime.now().add(const Duration(days: 304)),
      );
      final required = g.requiredMonthlyContribution;
      expect(required, isNotNull);
      // Roughly ten months of 30,000.
      expect(required!.amount, closeTo(30000, 1500));
    });

    test('no target date means no monthly figure to compute', () {
      expect(goal().requiredMonthlyContribution, isNull);
    });

    test('a reached goal needs no further contribution', () {
      final g = goal(
        target: 100000,
        current: 100000,
        targetDate: DateTime.now().add(const Duration(days: 60)),
      );
      expect(g.requiredMonthlyContribution, isNull);
    });

    test('an unmet goal past its date is overdue', () {
      final g = goal(
        current: 1000,
        targetDate: DateTime.now().subtract(const Duration(days: 10)),
      );
      expect(g.isOverdue, isTrue);
      expect(g.daysRemaining, lessThan(0));
    });

    test('a reached goal past its date is not overdue', () {
      final g = goal(
        target: 1000,
        current: 1000,
        targetDate: DateTime.now().subtract(const Duration(days: 10)),
      );
      expect(g.isOverdue, isFalse);
    });

    test('a withdrawal is stored as a negative contribution', () {
      final withdrawal = SavingsContribution(
        id: 'c-1',
        goalId: 'g-1',
        amount: Money.fromMajor(-5000),
        occurredOn: DateTime(2026, 9, 15),
        createdAt: DateTime(2026, 9, 15),
      );
      expect(withdrawal.isWithdrawal, isTrue);
    });
  });

  // --- Bills ----------------------------------------------------------------

  group('Bill', () {
    Bill bill({
      required int daysFromNow,
      BillStatus status = BillStatus.unpaid,
      RecurrenceFrequency? frequency,
    }) =>
        Bill(
          id: 'bill-1',
          userId: 'user-1',
          name: 'Electricity',
          amount: Money.fromMajor(8500),
          dueDate: DateTime.now().add(Duration(days: daysFromNow)),
          status: status,
          frequency: frequency,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    test('a past due date reads as overdue regardless of the stored status', () {
      // Derived rather than trusted, so the list is right even before the daily
      // job has run.
      final overdue = bill(daysFromNow: -3);
      expect(overdue.effectiveStatus, BillStatus.overdue);
      expect(overdue.isOverdue, isTrue);
      expect(overdue.bucket, BillBucket.overdue);
    });

    test('buckets by urgency', () {
      expect(bill(daysFromNow: 0).bucket, BillBucket.dueToday);
      expect(bill(daysFromNow: 1).bucket, BillBucket.dueTomorrow);
      expect(bill(daysFromNow: 4).bucket, BillBucket.dueThisWeek);
      expect(bill(daysFromNow: 20).bucket, BillBucket.upcoming);
    });

    test('a paid bill stays paid even if its date has passed', () {
      final paid = bill(daysFromNow: -5, status: BillStatus.paid);
      expect(paid.effectiveStatus, BillStatus.paid);
      expect(paid.isOverdue, isFalse);
      expect(paid.bucket, BillBucket.paid);
    });

    test('reminders fire inside the reminder window only', () {
      expect(bill(daysFromNow: 2).shouldRemindToday, isTrue);
      expect(bill(daysFromNow: 10).shouldRemindToday, isFalse);
      expect(
        bill(daysFromNow: 2, status: BillStatus.paid).shouldRemindToday,
        isFalse,
      );
    });

    test('a recurring bill knows its next due date', () {
      final recurring = bill(
        daysFromNow: 0,
        frequency: RecurrenceFrequency.monthly,
      );
      expect(recurring.isRecurring, isTrue);
      expect(recurring.nextDueDate, isNotNull);
    });

    test('outstanding total covers unpaid and overdue only', () {
      final total = BillTotals.outstanding([
        bill(daysFromNow: 3),
        bill(daysFromNow: -2),
        bill(daysFromNow: -8, status: BillStatus.paid),
        bill(daysFromNow: 5, status: BillStatus.cancelled),
      ], 'LKR');

      expect(total, Money.fromMajor(17000));
    });
  });

  // --- Subscriptions --------------------------------------------------------

  group('Subscription cost normalisation', () {
    Subscription subscription({
      double amount = 1790,
      RecurrenceFrequency frequency = RecurrenceFrequency.monthly,
      bool isActive = true,
    }) =>
        Subscription(
          id: 's-1',
          userId: 'user-1',
          name: 'Netflix',
          amount: Money.fromMajor(amount),
          frequency: frequency,
          nextRenewalDate: DateTime.now().add(const Duration(days: 6)),
          isActive: isActive,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    test('a monthly plan costs its own amount per month', () {
      expect(subscription().monthlyCost, Money.fromMajor(1790));
    });

    test('a yearly plan is divided across twelve months', () {
      final yearly = subscription(
        amount: 8900,
        frequency: RecurrenceFrequency.yearly,
      );
      expect(yearly.monthlyCost.amount, closeTo(741.67, 1));
    });

    test('mixed billing periods add up to one monthly figure', () {
      // The number users want: "what do subscriptions cost me a month".
      final total = SubscriptionTotals.monthly([
        subscription(amount: 1790),
        subscription(amount: 749),
        subscription(amount: 8900, frequency: RecurrenceFrequency.yearly),
      ], 'LKR');

      expect(total.amount, closeTo(3280, 2));
    });

    test('paused subscriptions are excluded from the total', () {
      final total = SubscriptionTotals.monthly([
        subscription(amount: 1000),
        subscription(amount: 5000, isActive: false),
      ], 'LKR');

      expect(total, Money.fromMajor(1000));
    });

    test('yearly total is twelve times the monthly figure', () {
      final subs = [subscription(amount: 1000)];
      expect(
        SubscriptionTotals.yearly(subs, 'LKR'),
        Money.fromMajor(12000),
      );
    });

    test('renewing soon is bounded by the reminder window', () {
      final soon = SubscriptionTotals.renewingSoon(
        [subscription()],
        days: 14,
      );
      expect(soon, hasLength(1));
    });
  });

  // --- Grouping -------------------------------------------------------------

  group('TransactionRepository.groupByDay', () {
    test('groups by calendar day, newest first', () {
      final groups = TransactionGrouping.byDay([
        transaction(id: '1', date: DateTime(2026, 9, 15, 9)),
        transaction(id: '2', date: DateTime(2026, 9, 15, 18)),
        transaction(id: '3', date: DateTime(2026, 9, 14, 12)),
      ]);

      expect(groups, hasLength(2));
      expect(groups.first.date, DateTime(2026, 9, 15));
      expect(groups.first.transactions, hasLength(2));
      expect(groups.last.date, DateTime(2026, 9, 14));
    });

    test('a day net excludes transfers', () {
      final group = TransactionGrouping.byDay([
        transaction(
          id: '1',
          type: TransactionType.expense,
          amount: 1000,
          date: DateTime(2026, 9, 15),
        ),
        transaction(
          id: '2',
          type: TransactionType.transfer,
          amount: 50000,
          direction: TransferDirection.out,
          date: DateTime(2026, 9, 15),
        ),
      ]).first;

      // Only the expense moves the figure; the transfer is internal.
      expect(group.net('LKR'), Money.fromMajor(-1000));
    });

    test('an empty list produces no groups', () {
      expect(TransactionGrouping.byDay(const []), isEmpty);
    });
  });

  // --- Split totals ---------------------------------------------------------

  group('Transaction splits', () {
    TransactionSplit split(double amount) => TransactionSplit(
          id: 's-$amount',
          transactionId: 'txn-1',
          amount: Money.fromMajor(amount),
        );

    test('the split total sums the lines', () {
      final parent = Transaction(
        id: 'txn-1',
        userId: 'user-1',
        accountId: 'acc-1',
        type: TransactionType.expense,
        amount: Money.fromMajor(10000),
        transactionDate: DateTime(2026, 9, 15),
        isSplit: true,
        splits: [split(6000), split(2500), split(1500)],
        createdAt: DateTime(2026, 9, 15),
        updatedAt: DateTime(2026, 9, 15),
      );

      expect(parent.splitTotal, Money.fromMajor(10000));
      expect(parent.hasSplitMismatch, isFalse);
    });

    test('a mismatch is detected', () {
      final parent = Transaction(
        id: 'txn-1',
        userId: 'user-1',
        accountId: 'acc-1',
        type: TransactionType.expense,
        amount: Money.fromMajor(10000),
        transactionDate: DateTime(2026, 9, 15),
        isSplit: true,
        splits: [split(6000), split(2500)],
        createdAt: DateTime(2026, 9, 15),
        updatedAt: DateTime(2026, 9, 15),
      );

      expect(parent.splitTotal, Money.fromMajor(8500));
      expect(parent.hasSplitMismatch, isTrue);
    });
  });

  // --- OCR candidates -------------------------------------------------------

  group('TransactionCandidate review rules', () {
    TransactionCandidate candidate({
      double? amount = 8450,
      DateTime? date,
      String? merchant = 'ABC Supermarket',
      String? accountId,
      String? categoryId = 'cat-1',
      Map<String, double> confidence = const {
        'amount': 0.99,
        'date': 0.95,
        'merchant': 0.96,
      },
    }) {
      return TransactionCandidate(
        id: 'cand-1',
        jobId: 'job-1',
        documentId: 'doc-1',
        userId: 'user-1',
        type: TransactionType.expense,
        amount: amount == null ? null : Money.fromMajor(amount),
        transactionDate: date ?? DateTime(2026, 9, 15),
        merchant: merchant,
        accountId: accountId,
        suggestedCategoryId: categoryId,
        fieldConfidence: confidence,
        createdAt: DateTime(2026, 9, 15),
        updatedAt: DateTime(2026, 9, 15),
      );
    }

    test('a field with no confidence score counts as needing verification', () {
      // Silence is not confidence. A missing score must not read as certainty.
      final c = candidate(confidence: const {});
      expect(c.needsVerification('amount'), isTrue);
      expect(c.needsVerification('date'), isTrue);
    });

    test('a high score does not need verification', () {
      expect(candidate().needsVerification('amount'), isFalse);
    });

    test('a score below the threshold needs verification', () {
      final c = candidate(confidence: const {'amount': 0.99, 'date': 0.72});
      expect(c.needsVerification('date'), isTrue);
    });

    test('a missing account blocks confirmation', () {
      // The parser never guesses an account, so this is always the user's call.
      final c = candidate();
      expect(c.accountId, isNull);
      expect(c.canConfirm, isFalse);
      expect(
        c.warnings.any((w) => w.blocking && w.title.contains('Account')),
        isTrue,
      );
    });

    test('a missing amount blocks confirmation', () {
      final c = candidate(amount: null, accountId: 'acc-1');
      expect(c.canConfirm, isFalse);
      expect(
        c.warnings.any((w) => w.blocking && w.title.contains('Amount')),
        isTrue,
      );
    });

    test('a complete candidate can be confirmed', () {
      final c = candidate(accountId: 'acc-1');
      expect(c.canConfirm, isTrue);
    });

    test('a low-confidence date warns but does not block', () {
      final c = candidate(
        accountId: 'acc-1',
        confidence: const {'amount': 0.99, 'date': 0.62, 'merchant': 0.9},
      );
      expect(c.canConfirm, isTrue);
      expect(
        c.warnings.any((w) => !w.blocking && w.title.contains('Date')),
        isTrue,
      );
    });

    test('toTransaction refuses to build without an amount', () {
      // The last line of defence before the database's own check.
      expect(
        () => candidate(amount: null).toTransaction(
          accountId: 'acc-1',
          source: TransactionSource.ocrImage,
        ),
        throwsStateError,
      );
    });

    test('toTransaction carries the approved values through', () {
      final built = candidate().toTransaction(
        accountId: 'acc-9',
        source: TransactionSource.ocrImage,
        categoryId: 'cat-override',
      );

      expect(built.accountId, 'acc-9');
      expect(built.categoryId, 'cat-override');
      expect(built.amount, Money.fromMajor(8450));
      expect(built.source, TransactionSource.ocrImage);
      // Confirmation is the act that makes it real, so the result is confirmed.
      expect(built.status, TransactionStatus.confirmed);
      expect(built.documentId, 'doc-1');
    });

    test('a possible duplicate is surfaced as a warning, not a block', () {
      final c = TransactionCandidate(
        id: 'cand-2',
        jobId: 'job-1',
        documentId: 'doc-1',
        userId: 'user-1',
        type: TransactionType.expense,
        amount: Money.fromMajor(8450),
        transactionDate: DateTime(2026, 9, 15),
        merchant: 'ABC',
        accountId: 'acc-1',
        suggestedCategoryId: 'cat-1',
        duplicateOfTransactionId: 'txn-existing',
        fieldConfidence: const {'amount': 0.99, 'date': 0.95, 'merchant': 0.9},
        createdAt: DateTime(2026, 9, 15),
        updatedAt: DateTime(2026, 9, 15),
      );

      expect(c.isPossibleDuplicate, isTrue);
      expect(c.canConfirm, isTrue);
      expect(
        c.warnings.any((w) => w.title.contains('duplicate')),
        isTrue,
      );
    });
  });

  // --- Category breakdown ---------------------------------------------------

  group('CategoryBreakdown.topWithOther', () {
    test('folds the tail into a single Other slice', () {
      final items = [
        for (var i = 0; i < 8; i++)
          CategoryBreakdownItem(
            categoryId: 'cat-$i',
            categoryName: 'Category $i',
            total: Money.fromMajor(1000 - i * 100),
            transactionCount: 2,
            color: const Color(0xFF000000),
          ),
      ];
      final breakdown = CategoryBreakdown(
        items: items,
        total: items.map((e) => e.total).reduce((a, b) => a + b),
        range: DateRange(DateTime(2026, 9), DateTime(2026, 9, 30)),
      );

      final folded = breakdown.topWithOther(5, const Color(0xFF888888));

      expect(folded, hasLength(6));
      expect(folded.last.categoryName, 'Other');
      // The folded slice must preserve the total, or the chart lies.
      expect(
        folded.map((e) => e.total).reduce((a, b) => a + b),
        breakdown.total,
      );
      expect(folded.last.transactionCount, 6);
    });

    test('leaves a short list untouched', () {
      final items = [
        CategoryBreakdownItem(
          categoryId: 'cat-1',
          categoryName: 'Food',
          total: Money.fromMajor(100),
          transactionCount: 1,
          color: const Color(0xFF000000),
        ),
      ];
      final breakdown = CategoryBreakdown(
        items: items,
        total: Money.fromMajor(100),
        range: DateRange(DateTime(2026, 9), DateTime(2026, 9, 30)),
      );

      expect(breakdown.topWithOther(5, const Color(0xFF888888)), hasLength(1));
    });
  });

  // --- Time series ----------------------------------------------------------

  group('TimeSeries', () {
    test('cumulative net accumulates each period', () {
      final series = TimeSeries(
        currency: 'LKR',
        points: [
          TimeSeriesPoint(
            periodStart: DateTime(2026, 7),
            label: 'Jul',
            income: Money.fromMajor(100000),
            expenses: Money.fromMajor(60000),
          ),
          TimeSeriesPoint(
            periodStart: DateTime(2026, 8),
            label: 'Aug',
            income: Money.fromMajor(100000),
            expenses: Money.fromMajor(120000),
          ),
          TimeSeriesPoint(
            periodStart: DateTime(2026, 9),
            label: 'Sep',
            income: Money.fromMajor(100000),
            expenses: Money.fromMajor(50000),
          ),
        ],
      );

      final cumulative = series.cumulativeNet;
      expect(cumulative[0], Money.fromMajor(40000));
      expect(cumulative[1], Money.fromMajor(20000));
      expect(cumulative[2], Money.fromMajor(70000));
    });

    test('max value considers both series', () {
      final series = TimeSeries(
        currency: 'LKR',
        points: [
          TimeSeriesPoint(
            periodStart: DateTime(2026, 9),
            label: 'Sep',
            income: Money.fromMajor(50000),
            expenses: Money.fromMajor(80000),
          ),
        ],
      );
      expect(series.maxValue, Money.fromMajor(80000));
    });

    test('an empty series has a zero maximum', () {
      const series = TimeSeries(points: <TimeSeriesPoint>[], currency: 'LKR');
      expect(series.maxValue, Money.zero());
      expect(series.isEmpty, isTrue);
    });
  });

  // --- Merchant totals ------------------------------------------------------

  group('MerchantTotal', () {
    test('average divides the total by the count', () {
      final merchant = MerchantTotal(
        merchant: 'Keells',
        total: Money.zero(),
        transactionCount: 0,
      );
      // No transactions must not divide by zero.
      expect(merchant.average, Money.zero());

      final real = MerchantTotal(
        merchant: 'Keells',
        total: Money.fromMajor(30000),
        transactionCount: 4,
      );
      expect(real.average, Money.fromMajor(7500));
    });
  });
}
