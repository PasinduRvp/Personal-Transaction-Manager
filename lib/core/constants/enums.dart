/// Domain enums. Every value maps to the exact string stored in PostgreSQL so
/// the database remains the single source of truth for valid values.
library;

/// Parses a database string into an enum value with a safe fallback.
T _parse<T>(List<T> values, String Function(T) wire, String? raw, T fallback) {
  if (raw == null) return fallback;
  final needle = raw.toUpperCase();
  for (final v in values) {
    if (wire(v) == needle) return v;
  }
  return fallback;
}

enum TransactionType {
  expense('EXPENSE', 'Expense'),
  income('INCOME', 'Income'),
  transfer('TRANSFER', 'Transfer');

  const TransactionType(this.wire, this.label);
  final String wire;
  final String label;

  static TransactionType fromWire(String? raw) =>
      _parse(values, (v) => v.wire, raw, TransactionType.expense);

  bool get isTransfer => this == TransactionType.transfer;

  /// Transfers move money between the user's own accounts, so they must never
  /// be counted as income or expense in analytics.
  bool get affectsCashflow => this != TransactionType.transfer;
}

/// Which leg of a transfer a row represents. Null on income and expense rows.
enum TransferDirection {
  out('OUT', 'Transfer out'),
  incoming('IN', 'Transfer in');

  const TransferDirection(this.wire, this.label);
  final String wire;
  final String label;

  static TransferDirection? fromWire(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return raw.toUpperCase() == 'IN' ? incoming : out;
  }
}

enum TransactionSource {
  manual('MANUAL', 'Manual'),
  ocrImage('OCR_IMAGE', 'Scanned image'),
  ocrPdf('OCR_PDF', 'Scanned PDF'),
  imported('IMPORTED', 'Imported');

  const TransactionSource(this.wire, this.label);
  final String wire;
  final String label;

  static TransactionSource fromWire(String? raw) =>
      _parse(values, (v) => v.wire, raw, TransactionSource.manual);

  bool get isOcr =>
      this == TransactionSource.ocrImage || this == TransactionSource.ocrPdf;
}

enum TransactionStatus {
  confirmed('CONFIRMED', 'Confirmed'),
  pending('PENDING', 'Pending');

  const TransactionStatus(this.wire, this.label);
  final String wire;
  final String label;

  static TransactionStatus fromWire(String? raw) =>
      _parse(values, (v) => v.wire, raw, TransactionStatus.confirmed);
}

enum AccountType {
  cash('CASH', 'Cash'),
  bank('BANK_ACCOUNT', 'Bank Account'),
  savings('SAVINGS_ACCOUNT', 'Savings Account'),
  debitCard('DEBIT_CARD', 'Debit Card'),
  creditCard('CREDIT_CARD', 'Credit Card'),
  eWallet('E_WALLET', 'E-wallet'),
  other('OTHER', 'Other');

  const AccountType(this.wire, this.label);
  final String wire;
  final String label;

  static AccountType fromWire(String? raw) =>
      _parse(values, (v) => v.wire, raw, AccountType.other);

  /// Credit cards carry a credit limit and a debt-style balance.
  bool get isCredit => this == AccountType.creditCard;
}

enum CategoryKind {
  expense('EXPENSE', 'Expense'),
  income('INCOME', 'Income');

  const CategoryKind(this.wire, this.label);
  final String wire;
  final String label;

  static CategoryKind fromWire(String? raw) =>
      _parse(values, (v) => v.wire, raw, CategoryKind.expense);
}

enum PaymentMethod {
  cash('CASH', 'Cash'),
  debitCard('DEBIT_CARD', 'Debit Card'),
  creditCard('CREDIT_CARD', 'Credit Card'),
  bankTransfer('BANK_TRANSFER', 'Bank Transfer'),
  onlineBanking('ONLINE_BANKING', 'Online Banking'),
  eWallet('E_WALLET', 'E-wallet'),
  qrPayment('QR_PAYMENT', 'QR Payment'),
  other('OTHER', 'Other');

  const PaymentMethod(this.wire, this.label);
  final String wire;
  final String label;

  static PaymentMethod? fromWire(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final needle = raw.toUpperCase();
    for (final v in values) {
      if (v.wire == needle) return v;
    }
    return PaymentMethod.other;
  }
}

enum BudgetPeriod {
  weekly('WEEKLY', 'Weekly'),
  monthly('MONTHLY', 'Monthly'),
  yearly('YEARLY', 'Yearly'),
  custom('CUSTOM', 'Custom');

  const BudgetPeriod(this.wire, this.label);
  final String wire;
  final String label;

  static BudgetPeriod fromWire(String? raw) =>
      _parse(values, (v) => v.wire, raw, BudgetPeriod.monthly);
}

enum RecurrenceFrequency {
  daily('DAILY', 'Daily'),
  weekly('WEEKLY', 'Weekly'),
  biweekly('BIWEEKLY', 'Every 2 weeks'),
  monthly('MONTHLY', 'Monthly'),
  quarterly('QUARTERLY', 'Quarterly'),
  yearly('YEARLY', 'Yearly'),
  custom('CUSTOM', 'Custom');

  const RecurrenceFrequency(this.wire, this.label);
  final String wire;
  final String label;

  static RecurrenceFrequency fromWire(String? raw) =>
      _parse(values, (v) => v.wire, raw, RecurrenceFrequency.monthly);
}

enum BillStatus {
  unpaid('UNPAID', 'Unpaid'),
  paid('PAID', 'Paid'),
  overdue('OVERDUE', 'Overdue'),
  cancelled('CANCELLED', 'Cancelled');

  const BillStatus(this.wire, this.label);
  final String wire;
  final String label;

  static BillStatus fromWire(String? raw) =>
      _parse(values, (v) => v.wire, raw, BillStatus.unpaid);
}

enum DocumentType {
  receipt('RECEIPT', 'Receipt'),
  bankStatement('BANK_STATEMENT', 'Bank statement'),
  invoice('INVOICE', 'Invoice'),
  paymentReceipt('PAYMENT_RECEIPT', 'Payment receipt'),
  other('OTHER', 'Other'),
  unknown('UNKNOWN', 'Unknown');

  const DocumentType(this.wire, this.label);
  final String wire;
  final String label;

  static DocumentType fromWire(String? raw) =>
      _parse(values, (v) => v.wire, raw, DocumentType.unknown);

  /// Statements yield many candidates; receipts and invoices yield one.
  bool get isMultiTransaction => this == DocumentType.bankStatement;
}

enum OcrJobStatus {
  queued('QUEUED', 'Queued'),
  processing('PROCESSING', 'Processing'),
  completed('COMPLETED', 'Completed'),
  partiallyCompleted('PARTIALLY_COMPLETED', 'Partially completed'),
  failed('FAILED', 'Failed'),
  cancelled('CANCELLED', 'Cancelled');

  const OcrJobStatus(this.wire, this.label);
  final String wire;
  final String label;

  static OcrJobStatus fromWire(String? raw) =>
      _parse(values, (v) => v.wire, raw, OcrJobStatus.queued);

  bool get isTerminal =>
      this == OcrJobStatus.completed ||
      this == OcrJobStatus.partiallyCompleted ||
      this == OcrJobStatus.failed ||
      this == OcrJobStatus.cancelled;

  bool get isSuccessful =>
      this == OcrJobStatus.completed || this == OcrJobStatus.partiallyCompleted;
}

enum OcrCandidateStatus {
  pending('PENDING', 'Needs review'),
  confirmed('CONFIRMED', 'Confirmed'),
  ignored('IGNORED', 'Ignored'),
  duplicate('DUPLICATE', 'Possible duplicate');

  const OcrCandidateStatus(this.wire, this.label);
  final String wire;
  final String label;

  static OcrCandidateStatus fromWire(String? raw) =>
      _parse(values, (v) => v.wire, raw, OcrCandidateStatus.pending);
}

enum NotificationKind {
  budgetWarning('BUDGET_WARNING', 'Budget approaching limit'),
  budgetExceeded('BUDGET_EXCEEDED', 'Budget exceeded'),
  billDue('BILL_DUE', 'Upcoming bill'),
  subscriptionRenewal('SUBSCRIPTION_RENEWAL', 'Subscription renewal'),
  recurringDue('RECURRING_DUE', 'Recurring transaction'),
  ocrCompleted('OCR_COMPLETED', 'Document processed'),
  ocrFailed('OCR_FAILED', 'Document failed'),
  goalReached('GOAL_REACHED', 'Savings goal reached'),
  creditCardDue('CREDIT_CARD_DUE', 'Credit card payment due');

  const NotificationKind(this.wire, this.label);
  final String wire;
  final String label;

  static NotificationKind fromWire(String? raw) =>
      _parse(values, (v) => v.wire, raw, NotificationKind.ocrCompleted);
}

enum AppThemeMode {
  system('SYSTEM', 'System'),
  light('LIGHT', 'Light'),
  dark('DARK', 'Dark');

  const AppThemeMode(this.wire, this.label);
  final String wire;
  final String label;

  static AppThemeMode fromWire(String? raw) =>
      _parse(values, (v) => v.wire, raw, AppThemeMode.system);
}

enum TransactionSort {
  newest('Newest first'),
  oldest('Oldest first'),
  amountHigh('Highest amount'),
  amountLow('Lowest amount'),
  merchantAsc('Merchant A-Z'),
  merchantDesc('Merchant Z-A');

  const TransactionSort(this.label);
  final String label;
}

enum DateRangePreset {
  week('This week'),
  month('This month'),
  threeMonths('Last 3 months'),
  sixMonths('Last 6 months'),
  year('This year'),
  custom('Custom');

  const DateRangePreset(this.label);
  final String label;
}

/// Which way a lending record runs.
///
/// Reuses [TransferDirection] for the actual money movement on each entry (the
/// principal and every repayment are each a transfer-typed transaction with no
/// peer account) — this enum only says who ends up owing whom.
enum LendingKind {
  /// You gave the money. The other person owes you (a receivable).
  lent('LENT', 'You lent'),

  /// You received the money. You owe the other person (a payable).
  borrowed('BORROWED', 'You borrowed');

  const LendingKind(this.wire, this.label);
  final String wire;
  final String label;

  static LendingKind fromWire(String? raw) =>
      _parse(values, (v) => v.wire, raw, LendingKind.lent);

  /// True when the principal was money leaving your account.
  bool get isReceivable => this == LendingKind.lent;
}

