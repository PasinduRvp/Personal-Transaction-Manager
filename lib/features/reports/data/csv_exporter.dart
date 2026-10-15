import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';

import '../../../core/utils/app_date_utils.dart';
import '../../../shared/models/transaction.dart';

/// Exports transactions as CSV.
///
/// The column set is deliberately the full record rather than a summary: the
/// point of an export is that the user can take their data elsewhere, and a
/// lossy export is not really an export.
class CsvExporter {
  const CsvExporter._();

  static const List<String> columns = [
    'Date',
    'Time',
    'Type',
    'Merchant',
    'Description',
    'Category',
    'Account',
    'Payment Method',
    'Amount',
    'Signed Amount',
    'Currency',
    'Source',
    'Status',
    'Reference',
    'Notes',
    'Split Items',
  ];

  static String build(List<Transaction> transactions) {
    final rows = <List<String>>[
      columns,
      for (final transaction in transactions) _rowFor(transaction),
    ];

    // CRLF, because Excel on Windows is the most common destination for this
    // file and treats bare LF inconsistently.
    return const ListToCsvConverter(eol: '\r\n').convert(rows);
  }

  /// UTF-8 with a byte-order mark, so Excel renders non-ASCII merchant names and
  /// currency symbols correctly instead of mojibake.
  static Uint8List toBytes(String csv) {
    const bom = [0xEF, 0xBB, 0xBF];
    return Uint8List.fromList([...bom, ...utf8.encode(csv)]);
  }

  static List<String> _rowFor(Transaction transaction) {
    final splits = transaction.splits
        .map((s) => '${s.label}: ${s.amount.format(showSymbol: false)}')
        .join(' | ');

    return [
      DateDisplay.iso(transaction.transactionDate),
      DateDisplay.time(transaction.transactionDate),
      _typeLabel(transaction),
      transaction.merchant ?? '',
      transaction.description ?? '',
      transaction.category?.name ?? '',
      transaction.account?.name ?? '',
      transaction.paymentMethod?.label ?? '',
      // Unsigned magnitude and signed value in separate columns: the first is
      // what a receipt says, the second is what a spreadsheet can sum.
      transaction.amount.format(showSymbol: false),
      transaction.signedAmount.format(showSymbol: false),
      transaction.currency,
      transaction.source.label,
      transaction.status.label,
      transaction.referenceNumber ?? '',
      (transaction.notes ?? '').replaceAll('\n', ' '),
      splits,
    ];
  }

  static String _typeLabel(Transaction transaction) {
    if (!transaction.type.isTransfer) return transaction.type.label;
    // Both legs of a transfer are exported, so each needs to say which it is.
    final direction = transaction.transferDirection?.label ?? 'Transfer';
    final peer = transaction.transferPeerAccount?.name;
    return peer == null ? direction : '$direction ($peer)';
  }

  /// A filename that sorts chronologically and says what it contains.
  static String fileNameFor(DateRange range) {
    final start = DateDisplay.iso(range.start);
    final end = DateDisplay.iso(range.end);
    return start == end
        ? 'finora-transactions-$start.csv'
        : 'finora-transactions-${start}_to_$end.csv';
  }
}
