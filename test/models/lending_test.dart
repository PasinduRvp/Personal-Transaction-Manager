import 'package:finora/core/constants/enums.dart';
import 'package:finora/core/utils/money.dart';
import 'package:finora/shared/models/lending.dart';
import 'package:flutter_test/flutter_test.dart';

/// The lending rules that matter financially: who owes what after a charge,
/// and how a record moves through its statuses as instalments arrive.
///
/// These assert the worked examples from the specification directly, so a
/// change that quietly folds a bank charge into someone's debt fails here.
LendingRecord record({
  required LendingKind kind,
  required int principalMinor,
  required int outstandingMinor,
  LendingMethod method = LendingMethod.wallet,
  int? transferMinor,
  int? chargeMinor,
}) {
  final now = DateTime(2026, 1, 1);
  return LendingRecord(
    id: 'l1',
    userId: 'u1',
    personName: 'John',
    kind: kind,
    principal: Money.fromMinorUnits(principalMinor),
    outstanding: Money.fromMinorUnits(outstandingMinor),
    accountId: 'a1',
    method: method,
    transferAmount: Money.fromMinorUnits(transferMinor ?? principalMinor),
    additionalCharge:
        chargeMinor == null ? null : Money.fromMinorUnits(chargeMinor),
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('Lending status', () {
    test('a record with nothing repaid is pending', () {
      final lending = record(
        kind: LendingKind.lent,
        principalMinor: 100000,
        outstandingMinor: 100000,
      );

      expect(lending.status, LendingStatus.pending);
      expect(lending.repaidAmount.minorUnits, 0);
      expect(lending.isSettled, isFalse);
    });

    test('a part-paid record is partially repaid', () {
      final lending = record(
        kind: LendingKind.lent,
        principalMinor: 100000,
        outstandingMinor: 50000,
      );

      expect(lending.status, LendingStatus.partiallyRepaid);
      expect(lending.repaidAmount.minorUnits, 50000);
    });

    test('a record with nothing outstanding is fully repaid', () {
      final lending = record(
        kind: LendingKind.lent,
        principalMinor: 100000,
        outstandingMinor: 0,
      );

      expect(lending.status, LendingStatus.fullyRepaid);
      expect(lending.status.isSettled, isTrue);
      expect(lending.repaidAmount.minorUnits, 100000);
    });

    test('borrowing moves through the same statuses', () {
      expect(
        record(
          kind: LendingKind.borrowed,
          principalMinor: 100000,
          outstandingMinor: 100000,
        ).status,
        LendingStatus.pending,
      );
      expect(
        record(
          kind: LendingKind.borrowed,
          principalMinor: 100000,
          outstandingMinor: 50000,
        ).status,
        LendingStatus.partiallyRepaid,
      );
      expect(
        record(
          kind: LendingKind.borrowed,
          principalMinor: 100000,
          outstandingMinor: 0,
        ).status,
        LendingStatus.fullyRepaid,
      );
    });
  });

  group('Instalments', () {
    test('three repayments walk the balance down to zero', () {
      // Rs 1,000 lent, repaid 500 then 300 then 200.
      const principal = 100000;

      for (final step in [
        (outstanding: 50000, repaid: 50000, status: LendingStatus.partiallyRepaid),
        (outstanding: 20000, repaid: 80000, status: LendingStatus.partiallyRepaid),
        (outstanding: 0, repaid: 100000, status: LendingStatus.fullyRepaid),
      ]) {
        final lending = record(
          kind: LendingKind.lent,
          principalMinor: principal,
          outstandingMinor: step.outstanding,
        );

        expect(lending.repaidAmount.minorUnits, step.repaid);
        expect(lending.status, step.status);
      }
    });
  });

  group('Bank transfer charge', () {
    test('the charge is the lender\'s cost, never the borrower\'s debt', () {
      // Rs 1,000 lent by bank transfer, Rs 25 charged by the bank.
      final lending = record(
        kind: LendingKind.lent,
        principalMinor: 100000,
        outstandingMinor: 100000,
        method: LendingMethod.bankTransfer,
        transferMinor: 100000,
        chargeMinor: 2500,
      );

      // What the borrower received, and still owes, excludes the charge.
      expect(lending.transferAmount.minorUnits, 100000);
      expect(lending.principal.minorUnits, 100000);
      expect(lending.outstanding.minorUnits, 100000);

      // What it cost the lender includes it.
      expect(lending.totalOutflow.minorUnits, 102500);
      expect(lending.hasCharge, isTrue);
    });

    test('a record without a charge costs exactly what was transferred', () {
      final lending = record(
        kind: LendingKind.lent,
        principalMinor: 100000,
        outstandingMinor: 100000,
      );

      expect(lending.hasCharge, isFalse);
      expect(lending.totalOutflow.minorUnits, 100000);
    });

    test('a zero charge does not count as a charge', () {
      final lending = record(
        kind: LendingKind.lent,
        principalMinor: 100000,
        outstandingMinor: 100000,
        method: LendingMethod.bankTransfer,
        chargeMinor: 0,
      );

      expect(lending.hasCharge, isFalse);
      expect(lending.totalOutflow.minorUnits, 100000);
    });
  });

  group('Lending method', () {
    test('only a bank transfer may carry a charge', () {
      expect(LendingMethod.bankTransfer.allowsAdditionalCharge, isTrue);
      expect(LendingMethod.wallet.allowsAdditionalCharge, isFalse);
      expect(LendingMethod.other.allowsAdditionalCharge, isFalse);
    });

    test('offers exactly wallet, bank transfer and other', () {
      expect(
        LendingMethod.values.map((m) => m.label),
        ['Wallet', 'Bank Transfer', 'Other'],
      );
    });

    test('maps onto the payment method a transaction records', () {
      expect(LendingMethod.wallet.asPaymentMethod, PaymentMethod.eWallet);
      expect(
        LendingMethod.bankTransfer.asPaymentMethod,
        PaymentMethod.bankTransfer,
      );
      expect(LendingMethod.other.asPaymentMethod, PaymentMethod.other);
    });

    test('an unknown stored value falls back to other', () {
      expect(LendingMethod.fromWire(null), LendingMethod.other);
      expect(LendingMethod.fromWire('CHEQUE'), LendingMethod.other);
      expect(LendingMethod.fromWire('WALLET'), LendingMethod.wallet);
    });
  });

  group('Direction', () {
    test('lending is a receivable, borrowing is not', () {
      expect(LendingKind.lent.isReceivable, isTrue);
      expect(LendingKind.borrowed.isReceivable, isFalse);
    });
  });
}
