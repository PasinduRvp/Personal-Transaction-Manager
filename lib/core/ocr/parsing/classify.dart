/// Document classification and merchant/category inference.
///
/// Classification decides which parser runs: a receipt yields one candidate, a bank
/// statement yields many. Getting it wrong is recoverable — the user sees the
/// candidates and can dismiss them — but getting it right is what makes the import
/// feel like it understood the document.
library;

class Classification {
  const Classification({
    required this.kind,
    required this.confidence,
    required this.signals,
  });

  /// `RECEIPT`, `BANK_STATEMENT`, `INVOICE`, `PAYMENT_RECEIPT` or `UNKNOWN`.
  final String kind;
  final double confidence;

  /// What was matched, for the "why did it decide that" panel.
  final List<String> signals;
}

class _Signal {
  const _Signal(this.pattern, this.weight, this.label);
  final RegExp pattern;
  final double weight;
  final String label;
}

RegExp _i(String source) => RegExp(source, caseSensitive: false);

final List<_Signal> _statementSignals = [
  _Signal(_i(r'\bstatement\s*of\s*account\b'), 0.45, 'statement of account'),
  _Signal(_i(r'\baccount\s*statement\b'), 0.45, 'account statement'),
  _Signal(_i(r'\bstatement\s*period\b'), 0.35, 'statement period'),
  _Signal(_i(r'\bopening\s*balance\b'), 0.30, 'opening balance'),
  _Signal(_i(r'\bclosing\s*balance\b'), 0.30, 'closing balance'),
  _Signal(_i(r'\bbalance\s*(?:b/f|forward|brought)\b'), 0.25, 'balance forward'),
  _Signal(_i(r'\b(debit|withdrawal)s?\b.*\b(credit|deposit)s?\b'), 0.30,
      'debit/credit columns'),
  _Signal(_i(r'\bvalue\s*date\b'), 0.20, 'value date'),
  _Signal(_i(r'\bavailable\s*balance\b'), 0.20, 'available balance'),
];

final List<_Signal> _receiptSignals = [
  _Signal(_i(r'\bthank\s*you\b'), 0.20, 'thank you'),
  _Signal(_i(r'\bcashier\b'), 0.25, 'cashier'),
  _Signal(_i(r'\b(bill|receipt)\s*(?:no|number|#)\b'), 0.30, 'receipt number'),
  _Signal(_i(r'\bsub\s*total\b'), 0.25, 'subtotal'),
  _Signal(_i(r'\b(vat|gst|nbt|svc\s*charge|service\s*charge)\b'), 0.20,
      'tax line'),
  _Signal(_i(r'\bqty\b|\bquantity\b'), 0.20, 'quantity column'),
  _Signal(_i(r'\bchange\b'), 0.20, 'change given'),
  _Signal(_i(r'\bcash\s*(?:tendered|paid)\b'), 0.20, 'cash tendered'),
  _Signal(_i(r'\bpos\b|\bterminal\s*id\b'), 0.20, 'POS terminal'),
];

final List<_Signal> _invoiceSignals = [
  _Signal(_i(r'\btax\s*invoice\b'), 0.50, 'tax invoice'),
  _Signal(_i(r'\binvoice\s*(?:no|number|#)\b'), 0.45, 'invoice number'),
  _Signal(_i(r'\bbill\s*to\b'), 0.30, 'bill to'),
  _Signal(_i(r'\bdue\s*date\b'), 0.25, 'due date'),
  _Signal(_i(r'\bpurchase\s*order\b'), 0.20, 'purchase order'),
  _Signal(_i(r'\bterms\b.*\bnet\s*\d+\b'), 0.20, 'payment terms'),
];

final List<_Signal> _paymentSignals = [
  _Signal(_i(r'\bpayment\s*receipt\b'), 0.50, 'payment receipt'),
  _Signal(_i(r'\bpayment\s*(?:confirmation|successful|success)\b'), 0.45,
      'payment confirmation'),
  _Signal(_i(r'\btransaction\s*(?:successful|reference)\b'), 0.30,
      'transaction reference'),
  _Signal(_i(r'\bpaid\s*(?:to|via)\b'), 0.25, 'paid to'),
  _Signal(_i(r'\bfund\s*transfer\b'), 0.30, 'fund transfer'),
];

class _Score {
  _Score(this.kind, this.score, this.signals);
  final String kind;
  double score;
  final List<String> signals;
}

Classification classifyDocument(String text) {
  final scores = <_Score>[];

  void evaluate(String kind, List<_Signal> signals) {
    final matched = <String>[];
    var score = 0.0;
    for (final signal in signals) {
      if (signal.pattern.hasMatch(text)) {
        score += signal.weight;
        matched.add(signal.label);
      }
    }
    scores.add(_Score(kind, score, matched));
  }

  evaluate('BANK_STATEMENT', _statementSignals);
  evaluate('RECEIPT', _receiptSignals);
  evaluate('INVOICE', _invoiceSignals);
  evaluate('PAYMENT_RECEIPT', _paymentSignals);

  // A document with many dated rows is a statement whatever its wording.
  final datedRowCount = _countDatedRows(text);
  final statement = scores.firstWhere((s) => s.kind == 'BANK_STATEMENT');
  if (datedRowCount >= 4) {
    final bonus = datedRowCount * 0.06;
    statement.score += bonus < 0.5 ? bonus : 0.5;
    statement.signals.add('$datedRowCount dated rows');
  }

  scores.sort((a, b) => b.score.compareTo(a.score));
  final winner = scores.first;

  if (winner.score < 0.35) {
    return Classification(
      kind: 'UNKNOWN',
      confidence: 0.3,
      signals: winner.signals,
    );
  }

  return Classification(
    kind: winner.kind,
    confidence:
        double.parse((winner.score < 1 ? winner.score : 1.0).toStringAsFixed(4)),
    signals: winner.signals,
  );
}

/// Rows that start with something date-shaped — the shape of a statement table.
int _countDatedRows(String text) => text
    .split(RegExp(r'\r?\n'))
    .where((line) => RegExp(
          r'^\s*(\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}|\d{1,2}\s+[A-Za-z]{3})\b',
        ).hasMatch(line))
    .length;

// ---------------------------------------------------------------------------
// Merchant
// ---------------------------------------------------------------------------

/// Lines that are never a merchant name.
final List<RegExp> _merchantNoise = [
  _i(r'^\s*(tel|phone|fax|email|e-mail|web|www|http)'),
  _i(r'^\s*(no\.?\s*\d|#\s*\d)'),
  _i(r'^\s*(vat|gst|tin|brn|reg(?:istration)?\s*no)'),
  RegExp(r'^[\d\s,./\-:()]+$'),
  _i(r'^\s*(invoice|receipt|bill|statement|date|time|cashier|terminal|customer)\b'),
  _i(r'^\s*(thank\s*you|welcome|visit\s*again)'),
  RegExp(r'^\s*[-=*_]{3,}\s*$'),
];

class MerchantGuess {
  const MerchantGuess(this.merchant, this.confidence);
  final String? merchant;
  final double confidence;
}

/// Guesses the merchant from the top of a receipt.
///
/// Merchants print their name in the first few lines, above the address. The
/// heuristic prefers the earliest line that is mostly letters, is not obviously an
/// address or a label, and is a plausible length.
MerchantGuess extractMerchant(List<String> lines) {
  final head = lines.take(8).toList();
  final candidates = <({String text, double score})>[];

  for (var index = 0; index < head.length; index++) {
    final trimmed = head[index].trim();
    if (trimmed.length < 3 || trimmed.length > 60) continue;
    if (_merchantNoise.any((p) => p.hasMatch(trimmed))) continue;

    final letters = RegExp(r'[A-Za-z]').allMatches(trimmed).length;
    final letterRatio = letters / trimmed.length;
    if (letterRatio < 0.55) continue;

    var score = 0.55 + letterRatio * 0.2;

    // Earlier is better.
    score -= index * 0.05;

    // ALL CAPS is the house style for receipt headers.
    if (trimmed == trimmed.toUpperCase() && letters >= 4) score += 0.12;

    // Company suffixes are a strong hint.
    if (_i(r'\b(pvt|ltd|plc|limited|inc|llc|co|company|stores?|supermarket|'
            r'mart|cafe|restaurant|hotel)\b')
        .hasMatch(trimmed)) {
      score += 0.15;
    }

    candidates.add((text: normaliseMerchant(trimmed), score: score));
  }

  if (candidates.isEmpty) return const MerchantGuess(null, 0);

  candidates.sort((a, b) => b.score.compareTo(a.score));
  final best = candidates.first;

  return MerchantGuess(
    best.text,
    double.parse(best.score.clamp(0.0, 0.95).toStringAsFixed(4)),
  );
}

/// `ABC  SUPERMARKET (PVT) LTD` → `ABC Supermarket (Pvt) LTD`.
String normaliseMerchant(String raw) {
  final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();

  // Leave mixed-case names alone; they are already how the merchant writes it.
  if (collapsed != collapsed.toUpperCase()) return collapsed;

  return collapsed.split(' ').map(_titleCaseWord).join(' ');
}

/// Title-cases one word of a shouted merchant name.
///
/// Three rules, in order:
///
///   * A known legal suffix stays upper case: `LTD`, `PLC`.
///   * A bare run of three letters or fewer is an initialism and is left alone —
///     `ABC`, `HNB`, `BOC` are how those names are written, and "Abc Supermarket"
///     reads as a mistake.
///   * Anything else is title-cased, *skipping leading punctuation*, so a bracketed
///     qualifier comes out as `(Pvt)` rather than having its bracket upper-cased.
String _titleCaseWord(String word) {
  final core = word.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (core.isEmpty) return word;

  if (_i(r'^(ltd|plc|llc|inc|uk|usa|atm|pos|hnb|boc|ceb|slt)$').hasMatch(core)) {
    return word.replaceAll(core, core.toUpperCase());
  }

  // Bracketed forms such as `(Pvt)` are legal qualifiers rather than initialisms,
  // so they are title-cased even when short.
  final isBare = core == word;
  if (isBare && core.length <= 3 && RegExp(r'^[A-Za-z]+$').hasMatch(core)) {
    return word;
  }

  final firstLetter = word.indexOf(RegExp(r'[A-Za-z]'));
  if (firstLetter == -1) return word;

  return word.substring(0, firstLetter) +
      word[firstLetter].toUpperCase() +
      word.substring(firstLetter + 1).toLowerCase();
}

// ---------------------------------------------------------------------------
// Payment method and reference
// ---------------------------------------------------------------------------

class PaymentGuess {
  const PaymentGuess(this.method, this.confidence);
  final String? method;
  final double confidence;
}

PaymentGuess extractPaymentMethod(String text) {
  final rules = <({RegExp pattern, String method, double confidence})>[
    (
      pattern: _i(r'\bvisa\b|\bmaster\s*card\b|\bmastercard\b|\bamex\b'),
      method: 'CREDIT_CARD',
      confidence: 0.8
    ),
    (pattern: _i(r'\bcredit\s*card\b'), method: 'CREDIT_CARD', confidence: 0.9),
    (pattern: _i(r'\bdebit\s*card\b'), method: 'DEBIT_CARD', confidence: 0.9),
    (
      pattern: _i(r'\b(cash|cash\s*sale|cash\s*tendered)\b'),
      method: 'CASH',
      confidence: 0.85
    ),
    (
      pattern: _i(r'\b(bank\s*transfer|fund\s*transfer|neft|rtgs|slips?|ceft)\b'),
      method: 'BANK_TRANSFER',
      confidence: 0.85
    ),
    (
      pattern: _i(r'\b(online\s*banking|internet\s*banking|net\s*banking)\b'),
      method: 'ONLINE_BANKING',
      confidence: 0.85
    ),
    (
      pattern: _i(r'\b(ez\s*cash|frimi|mcash|genie|payhere|e-?wallet|wallet)\b'),
      method: 'E_WALLET',
      confidence: 0.8
    ),
    (
      pattern: _i(r'\b(qr|lankaqr|scan\s*to\s*pay)\b'),
      method: 'QR_PAYMENT',
      confidence: 0.8
    ),
  ];

  for (final rule in rules) {
    if (rule.pattern.hasMatch(text)) {
      return PaymentGuess(rule.method, rule.confidence);
    }
  }
  return const PaymentGuess(null, 0);
}

class ReferenceGuess {
  const ReferenceGuess(this.reference, this.confidence);
  final String? reference;
  final double confidence;
}

ReferenceGuess extractReference(String text) {
  // The `\b` after the keyword group is load-bearing. Without it, `trans` matched
  // the first five letters of "Transaction" and the capture group took the rest of
  // the same word, so "Transaction Ref: TXN20260915AB" yielded "action".
  final patterns = [
    _i(r'\b(?:transaction|txn|trans|ref(?:erence)?)\b\s*(?:no\.?|number|id|#)?'
        r'\s*[:\-]?\s*([A-Z0-9][A-Z0-9\-/]{4,29})\b'),
    _i(r'\b(?:receipt|invoice|bill)\b\s*(?:no\.?|number|#)\s*[:\-]?\s*'
        r'([A-Z0-9][A-Z0-9\-/]{3,29})\b'),
    _i(r'\bapproval\s*(?:code|no\.?)\s*[:\-]?\s*([A-Z0-9]{4,12})\b'),
  ];

  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    if (match == null) continue;

    final value = match.group(1)!.trim();
    // A pure-digit "reference" that looks like a date or an amount is noise.
    if (RegExp(r'^\d{1,4}$').hasMatch(value)) continue;
    // So is a run of letters with no digit: a real reference carries a number, and
    // prose that happens to follow the word "reference" does not.
    if (!RegExp(r'\d').hasMatch(value)) continue;

    return ReferenceGuess(value, 0.75);
  }

  return const ReferenceGuess(null, 0);
}

// ---------------------------------------------------------------------------
// Category suggestion
// ---------------------------------------------------------------------------

/// Suggests a category *name* from the document text. The caller maps the name to
/// one of the user's own categories — the parser never invents a category id.
///
/// Keyword matching, not machine learning: it is predictable, auditable, and the
/// user corrects it in one tap when it is wrong.
final List<({String category, List<RegExp> patterns})> _categoryKeywords = [
  (
    category: 'Groceries',
    patterns: [
      _i(r'\b(supermarket|super\s*market|grocer|keells|cargills|arpico|'
          r'laugfs\s*super|glomark|spar|food\s*city)\b')
    ]
  ),
  (
    category: 'Food',
    patterns: [
      _i(r'\b(restaurant|cafe|coffee|bakery|pizza|burger|kfc|mcdonald|subway|'
          r'dominos|dine|kitchen|hotel\s*bar|canteen|food\s*court)\b')
    ]
  ),
  (
    category: 'Fuel',
    patterns: [
      _i(r'\b(fuel|petrol|diesel|ceypetco|ioc|lanka\s*ioc|filling\s*station|'
          r'gas\s*station)\b')
    ]
  ),
  (
    category: 'Transport',
    patterns: [
      _i(r'\b(uber|pickme|taxi|cab|bus\s*ticket|railway|train|parking|toll|'
          r'expressway)\b')
    ]
  ),
  (
    category: 'Utilities',
    patterns: [
      _i(r'\b(ceb|electricity|leco|water\s*board|nwsdb|gas\s*bill|litro|'
          r'laugfs\s*gas)\b')
    ]
  ),
  (
    category: 'Bills',
    patterns: [
      _i(r'\b(slt|mobitel|dialog|hutch|airtel|broadband|internet\s*bill|'
          r'telephone|postpaid)\b')
    ]
  ),
  (
    category: 'Healthcare',
    patterns: [
      _i(r'\b(pharmacy|hospital|clinic|medical|lab|channel(?:ling)?|osusala|'
          r'asiri|nawaloka|durdans|lanka\s*hospital)\b')
    ]
  ),
  (
    category: 'Shopping',
    patterns: [
      _i(r'\b(odel|fashion|clothing|apparel|nolimit|cool\s*planet|'
          r'house\s*of\s*fashion|mall|boutique|store)\b')
    ]
  ),
  (
    category: 'Entertainment',
    patterns: [
      _i(r'\b(cinema|scope|savoy|liberty|theatre|netflix|spotify|game|bowling|'
          r'amusement)\b')
    ]
  ),
  (
    category: 'Subscriptions',
    patterns: [
      _i(r'\b(subscription|netflix|spotify|youtube\s*premium|icloud|'
          r'google\s*one|dropbox|adobe|microsoft\s*365)\b')
    ]
  ),
  (
    category: 'Education',
    patterns: [
      _i(r'\b(school|university|campus|tuition|institute|course\s*fee|'
          r'exam\s*fee|sliit|nsbm|nibm)\b')
    ]
  ),
  (
    category: 'Insurance',
    patterns: [
      _i(r'\b(insurance|assurance|policy\s*premium|ceylinco|aia|allianz|'
          r'sri\s*lanka\s*insurance)\b')
    ]
  ),
  (category: 'Rent', patterns: [_i(r'\b(rent|rental|lease|landlord)\b')]),
  (
    category: 'Personal Care',
    patterns: [_i(r'\b(salon|spa|barber|beauty|cosmetic)\b')]
  ),
  (
    category: 'Travel',
    patterns: [
      _i(r'\b(airline|airways|flight|booking\.com|agoda|hotel\s*reservation|'
          r'visa\s*fee|srilankan)\b')
    ]
  ),
  (
    category: 'Salary',
    patterns: [_i(r'\b(salary|payroll|wages|remuneration)\b')]
  ),
];

class CategoryGuess {
  const CategoryGuess(this.name, this.confidence);
  final String? name;
  final double confidence;
}

CategoryGuess suggestCategoryName(String text) {
  for (final entry in _categoryKeywords) {
    for (final pattern in entry.patterns) {
      if (pattern.hasMatch(text)) {
        return CategoryGuess(entry.category, 0.75);
      }
    }
  }
  return const CategoryGuess(null, 0);
}
