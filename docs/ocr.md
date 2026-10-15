# OCR

The feature the app is built around, and the one with the most ways to go quietly
wrong.

## The rule

A document never becomes a transaction without a person looking at it first.

This is not a UI convention. It is enforced at three levels, and all three have
to be defeated to break it:

1. **The parser** returns `null` for anything it could not read. A missing amount
   stays missing; nothing is inferred to fill a gap.
2. **The pipeline** writes candidates to `ocr_transactions` and stops. The Edge
   Function has no code path that inserts into `transactions`.
3. **The database** does not grant clients `UPDATE` on
   `ocr_transactions.created_transaction_id`, and a check constraint requires one
   before `status` may be `CONFIRMED`. The only writer is
   `confirm_ocr_candidate`, which refuses without an amount, an account and a
   date.

A candidate with no amount cannot be confirmed by any route, including a direct
direct call with a valid ID token.

## Pipeline

```
 User picks a file (camera · gallery · image · PDF)
        │
        ▼
 ① Validate on device       extension, size, magic number
        │                   an unsupported file costs no bandwidth
        ▼
 ② Upload                   private bucket, path <user>/<doc>/<file>
        │                   SHA-256 recorded for re-upload detection
        ▼
 ③ Create document row      documents, ocr_status = QUEUED
        │
        ▼
 ④ Invoke ocr-process       user JWT → function verifies it
        │
        ├── validate size again server-side
        ├── download from storage
        │
        ▼
 ⑤ Read text
        │
        ├── image → provider.processImage()
        └── PDF  → text layer first; OCR only if there is none
        │
        ▼
 ⑥ Persist raw text         ocr_results, one row per page, immutable
        │                   written BEFORE parsing, so evidence survives a
        │                   parser crash
        ▼
 ⑦ Classify                 RECEIPT · BANK_STATEMENT · INVOICE · …
        │
        ▼
 ⑧ Parse                    receipt → one candidate
        │                   statement → one per row
        ▼
 ⑨ Persist candidates       ocr_transactions, status = PENDING
        │                   account_id deliberately NULL
        ▼
 ⑩ Flag duplicates          advisory only
        │
        ▼
 ⑪ Review screen            every field editable, confidence shown
        │
        ▼
 ⑫ User confirms  ──────▶  confirm_ocr_candidate()  ──▶  transactions
```

Step ⑥ before step ⑧ is deliberate: if parsing throws, the text is still stored
and the job can be re-parsed without re-reading the document or paying the
provider again.

## Provider abstraction

```dart
abstract interface class OcrProvider {
  String get name;
  bool get supportsPdf;
  int get maxPdfPages;

  Future<OcrProviderResult> processImage(OcrInput input);
  Future<OcrProviderResult> processPdf(OcrInput input);
}
```

`resolveProvider()` is the only function in the codebase that names a vendor.
Adding a fourth means one class and one case.

| Provider | Images | Text PDFs | Scanned PDFs | Notes |
|---|---|---|---|---|
| Google Vision | yes | yes* | no | `DOCUMENT_TEXT_DETECTION`, per-word confidence |
| Azure Document Intelligence | yes | yes* | **yes** | `prebuilt-read`, async, multi-page |
| AWS Textract | yes | yes* | 1 page | SigV4 signed by hand |

\* Text PDFs never reach the provider — they are read directly.

### Why Google cannot read scanned PDFs

Vision's synchronous `images:annotate` does not accept PDFs; its PDF support
requires Cloud Storage and an async job. Rather than pretend otherwise, the
pipeline raises `UNSUPPORTED_FILE` with a message telling the user to photograph
the document or switch provider. The alternative — silently reading page one, or
returning empty text — would be worse.

### Why Textract is signed by hand

The AWS SDK is large and a cold-starting serverless function paid for every byte it
imports. SigV4 is about sixty lines of WebCrypto, so the signing is implemented
directly in `aws_textract.ts`.

## PDFs: two paths

A bank statement exported from online banking is a **text PDF** — the characters
are really there. Running OCR on it would be slower, cost money, and be *less*
accurate than simply reading them. So:

```
PDF → extract text layer → usable?  ──yes──▶ parse (no OCR, no cost)
                                │
                                └──no───▶ provider.processPdf()
```

`extractPdfText()` inflates `/FlateDecode` content streams and pulls out the
text-showing operators (`Tj`, `TJ`, `'`, `"`), treating `Td`/`TD`/`T*`/`ET` as
line breaks — which is what keeps a statement's columns on separate lines so the
row parser can see them.

### The quality gate

This is the part that matters. A PDF whose text is written with subset fonts and
no `ToUnicode` map yields arbitrary glyph indices. A naive extractor reads those
as text, and a parser then produces confident-looking nonsense amounts.

`assessText()` rejects an extraction when:

- it is shorter than 24 characters
- more than 15% of it is unprintable
- fewer than 40% of its characters are letters or digits
- **it contains no digits at all** — a financial document that yielded no numbers
  is not a usable extraction, whatever else it contains

A rejected text layer falls through to OCR. Emitting plausible garbage into a
ledger is the one outcome worth engineering against.

## Parsing

Separate from recognition, on purpose. The provider's only job is text; the
parser's only job is interpretation. That split means the parser is testable
against fixed strings with no network and no API key — all 50 Deno tests run
offline — and an improved parser can be re-run over stored `ocr_results`.

### Amounts

Every number on a receipt is a candidate, and picking the wrong one is the most
damaging mistake available. So amounts are found *with their label* and scored:

| Signal | Weight |
|---|---|
| `GRAND TOTAL` | 1.00 |
| `TOTAL AMOUNT` / `AMOUNT DUE` / `TOTAL PAYABLE` | 0.96–0.98 |
| `NET TOTAL`, `BALANCE DUE` | 0.92–0.94 |
| `TOTAL` | 0.88 |
| In the bottom 40% of the document | +0.12 |
| Two decimal places | +0.08 |
| Largest value on the page | +0.10 |
| `SUB TOTAL`, `VAT`, `GST`, `CHANGE`, `DISCOUNT`, `QTY` | **−0.55** |

So on this receipt:

```
Rice 5kg          2,450.00
Cooking oil       9,800.00
SUB TOTAL        12,250.00
VAT 15%           1,837.50
TOTAL LKR        14,087.50
CASH             15,000.00
CHANGE              912.50
```

`14,087.50` wins. `15,000.00` is larger but unlabelled-and-penalised;
`12,250.00` is explicitly a subtotal.

Confidence reflects both the winner's score *and* its margin over the runner-up.
Two equally plausible totals produce low confidence, and the review screen flags
the field.

Separator handling decides decimal-versus-grouping by position rather than
locale: the right-most separator followed by exactly one or two digits is the
decimal point. That reads `8,450.00`, `8.450,00` and `8450,00` correctly without
being told where the user is.

OCR letter substitutions are repaired — `845O` → `8450`, `l0.00` → `10.00` — but
only when the input already contains a real digit. Without that guard the word
`TOTAL` parsed as `0`, which is exactly the class of silent wrong figure this
pipeline exists to prevent. (It did, once; there is a test for it now.)

### Dates

`15/09/2026` and `09/15/2026` are the same six characters in a different order,
and getting it wrong files a transaction in the wrong month.

```
day > 12  ────────────▶ day-first proven      confidence 0.95
month > 12 ───────────▶ month-first proven    confidence 0.95
both ≤ 12  ───────────▶ ambiguous             confidence 0.62  ← flagged
written month name ───▶ unambiguous           confidence 0.97
```

0.62 is below the 0.80 review threshold, so an ambiguous date always reaches the
user as "please verify" rather than as a silent guess. Day-first is the default
convention, matching most of the world including Sri Lanka.

Impossible dates (`31/02`) are rejected outright, as are dates outside a
plausible window — a year that reads as 2045 is a misread, not a prediction. A
`Due Date` or `Expiry` label drops the score to 35% of its value, because that is
not the transaction date.

### Bank statements

A statement is a table, and the columns matter: the same number is an expense in
the Debit column and income in the Credit column.

```
Date      Description              Debit       Credit      Balance
OPENING BALANCE                                          250,000.00
15/09/26  POS ABC SUPERMARKET      8,450.00              241,550.00
16/09/26  SALARY CREDIT SEP                  250,000.00  491,550.00
17/09/26  POS PICKME PVT LTD       1,800.00              489,750.00
CLOSING BALANCE                                          489,750.00
```

The running balance column is the main trap — it looks exactly like an amount.
It is detected by checking whether the last number on each row moves by roughly
the other numbers on that row, across rows, and then excluded. Opening and
closing balance rows are skipped by pattern.

Direction is decided in order: an explicit `DR`/`CR` suffix, a signed or bracketed
negative, then wording (`withdrawal`, `salary`, `refund`, …), then column
position. When nothing is conclusive the type is scored 0.50 — well below the
threshold — so the review screen asks rather than guessing between income and
expense.

### What is never guessed

**The account.** A statement does not identify which of the user's accounts it
belongs to, and a receipt certainly does not. `account_id` is left `NULL`, the
review screen marks it "Not detected", and confirmation is blocked until the user
picks one. The statement review screen says why, in one sentence, so the omission
reads as deliberate rather than broken.

**A category that does not exist.** If the parser suggests "Groceries" and the
user has no such category, the suggestion is dropped rather than created. The
parser does not get to add rows to someone's category list.

## Confidence

Per-field scores, stored as JSONB:

```json
{ "amount": 0.99, "date": 0.72, "merchant": 0.96, "payment_method": 0.8 }
```

The review screen maps them to four levels:

| Level | Range | Shown as |
|---|---|---|
| High | ≥ 0.92 | ✓ High confidence · 99% |
| Medium | ≥ 0.80 | ? Please check · 85% |
| Low | < 0.80 | ⚠ Please verify · 72% |
| Missing | no value | ⚠ Not detected |

**A field with no score counts as needing verification.** Silence is not
confidence, and treating an unscored field as certain is how a wrong figure gets
saved without anyone looking at it.

The percentage is shown alongside the verdict, because "probably right" and
"barely legible" are different situations and a binary hides that.

Confidence guides review. It never decides whether something is saved.

## Duplicate detection

Runs after parsing, before review. `find_duplicate_transactions` scores existing
transactions on reference, amount, date proximity, account and merchant
similarity; anything above 0.50 is recorded on the candidate.

The review screen then offers three choices and takes none of them
automatically:

```
Possible duplicate
Rs. 8,450.00 · ABC Supermarket · 15 Sep 2026
[Same amount] [Same date] [Similar merchant]

[ Skip ]  [ Not a duplicate ]
```

On a statement import, likely duplicates start **unticked**, so creating one is
opt-in rather than something to remember to prevent.

## Failures

Nine distinct kinds, each with its own message and suggestions. The user sees the
friendly form; the provider's own error text is logged and stored but never
rendered.

```
We couldn't read this document clearly.

Try uploading:
• Use a clearer, well-lit photo
• Hold the camera straight above the document
• Make sure the whole receipt is inside the frame
```

| Code | Means |
|---|---|
| `UNREADABLE` | Provider could not recognise the content |
| `NO_TEXT_FOUND` | No text in the document |
| `EMPTY_DOCUMENT` | Zero-byte file |
| `UNSUPPORTED_FILE` | Wrong type, or a scanned PDF on an image-only provider |
| `CORRUPT_FILE` | Damaged, or bytes contradicting the extension |
| `TOO_MANY_PAGES` | Over the page limit |
| `TIMEOUT` | Exceeded the processing window |
| `PROVIDER_UNAVAILABLE` | Auth failure, rate limit, or provider outage |
| `UNKNOWN` | Anything else |

A failed job stays in the history with its reason. A re-read creates a **new**
job rather than overwriting the old one, so the record of what happened stays
truthful.

A document that was read successfully but contained no transactions is reported
as *completed with zero candidates*, not as a failure — the read worked, there
was simply nothing to import, and conflating the two sends the user chasing a
problem that does not exist.

## Image preprocessing

Phone photos are over-large, slightly rotated and unevenly lit. Before OCR, a
copy is:

- rotated per EXIF orientation (phones record rotation in metadata and most
  providers ignore the tag)
- resized so the long edge is at most 2200px — text recognition gains nothing
  above that, while upload time and provider cost scale with pixels
- given a mild contrast lift (1.12) to help faint thermal receipts

The lift is deliberately gentle. Aggressive thresholding destroys thin digits, and
a wrong digit in an amount is worse than a slightly grey one.

**The original upload is never modified.** Preprocessing happens on a copy in
memory, so the receipt the user can reopen in six months is exactly what they
photographed. If preprocessing fails for any reason, the original bytes are sent
unchanged rather than the import failing.

## Testing

50 Deno tests, all offline:

```bash
flutter test test/core/parsing_test.dart
```

They cover amount selection against real receipt shapes, every date-ambiguity
case, statement row parsing with running-balance exclusion, Dr/Cr markers, and
the text-layer quality gate — including a case asserting that font-index noise is
*rejected* rather than parsed.
