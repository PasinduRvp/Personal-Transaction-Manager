# Finora

A personal transaction manager for Flutter and Firebase, built around one idea:
**you can photograph a receipt or upload a bank statement, and Finora will read
it — but nothing becomes a transaction until you have seen it and confirmed it.**

![Flutter](https://img.shields.io/badge/Flutter-3.35-blue)
![Dart](https://img.shields.io/badge/Dart-3.9-blue)
![Firebase](https://img.shields.io/badge/Firebase-Firestore-orange)
![Tests](https://img.shields.io/badge/tests-225%20passing-brightgreen)
![Plan](https://img.shields.io/badge/Firebase-free%20tier-brightgreen)

---

## What it does

Finora tracks income, spending, budgets and savings across multiple accounts,
and imports financial documents with OCR.

**Money**
- Multiple accounts: cash, bank, savings, debit and credit cards, e-wallets
- Expenses, income, and transfers between your own accounts
- Split one transaction across several categories
- Recurring schedules that post while the app is closed
- Bills with reminders, and subscriptions with a running monthly cost
- Budgets with configurable warning thresholds
- Savings goals with contributions, withdrawals and a required-monthly figure

**Documents and OCR**
- Import from camera, gallery, image file, or PDF
- Text-layer PDFs are read directly, with no OCR pass
- Text is recognised **on the device** — no API key, no upload, no cost
- Receipts yield one reviewable transaction; bank statements yield many
- Per-field confidence, so you can see what was read clearly and what was not
- Duplicate detection before import, advisory rather than automatic
- Import history that keeps failed attempts and their reasons

**Insight**
- Dashboard: balances, monthly cashflow, savings rate, budgets needing attention
- Analytics with eight views, every chart drilling through to its transactions
- Monthly PDF reports and CSV export

**Everything else**
- Light and dark themes from a single set of design tokens
- Works offline through Firestore's own persistence, including queued writes
- Loading, empty, error and success states on every screen
- Data export, document deletion, and account deletion

---

## The product rule

OCR output is never a transaction.

```
Upload → Validate → Store → OCR → Raw text → Parse → Candidate
                                                        ↓
                                              ┌─── Review screen ───┐
                                              │  edit any field     │
                                              │  see confidence     │
                                              │  check raw text     │
                                              └──────────┬──────────┘
                                                         ↓
                                          User confirms → Transaction
```

Enforced in four places, not one:

1. **The parser** returns `null` for a field it could not read, rather than a
   guess. A missing amount stays missing, and a document with nothing in it
   produces no candidate at all.
2. **The pipeline** writes to `ocrCandidates` and stops. `startJob` has no code
   path that creates a transaction.
3. **The security rules** require a candidate to be created `PENDING`, and refuse to
   let `created_transaction_id` be cleared once it is set — so the same receipt
   cannot be imported twice.
4. **`confirmCandidate`** writes the transaction and marks the candidate confirmed in
   a single Firestore transaction, and refuses to run without an amount, an account
   and a date.

A candidate with no amount cannot be confirmed through the app at all. And because
step 4 is atomic, a confirmed candidate always points at a transaction that exists.

Without a server, step 3 is weaker than it was: a modified client could write
`status` directly. See [docs/security.md](docs/security.md) for exactly what that
does and does not allow.

---

## Tech stack

| Layer | Choice | Why |
|---|---|---|
| App | Flutter 3.35, Dart 3.9 | One codebase for mobile, web and desktop |
| State | Riverpod 2.6 | Compile-safe dependency graph, testable by override |
| Routing | GoRouter 14 | Declarative routes with one central auth redirect |
| Backend | Firebase | Firestore and Auth, on the free Spark plan |
| Charts | fl_chart | Pure Dart, no platform channel |
| OCR | Google ML Kit, on-device | No key to leak, works offline, free |

---

## Architecture

```
lib/
├── core/                      Cross-cutting concerns
│   ├── config/                Compile-time limits (no credentials)
│   ├── constants/             Enums whose wire values match the documents
│   ├── errors/                Sealed exception hierarchy + error mapper
│   ├── ocr/                   On-device recognition and the parsers
│   │   ├── text_recogniser    ML Kit behind a swappable interface
│   │   └── parsing/           Amounts, dates, classification, statements
│   ├── routing/               Routes, router, shell
│   ├── services/              Firebase, document store, cache, connectivity
│   ├── theme/                 AppColors, AppTypography, AppSpacing, AppTheme
│   └── utils/                 Money, dates, validators
│
├── features/                  One folder per feature, presentation only
│   ├── auth/ dashboard/ transactions/ accounts/ categories/
│   ├── budgets/ savings/ bills/ subscriptions/ recurring/
│   ├── documents/ ocr/ analytics/ reports/ notifications/ profile/
│
├── shared/
│   ├── models/                Immutable domain models, plus pure calculations
│   ├── repositories/          The only code that knows Firestore exists
│   │   ├── ledger_writer      Balances, rollups and budgets, atomically
│   │   ├── account_seeder     Profile and 22 categories, idempotently
│   │   └── maintenance_runner Recurring posts and bill statuses, on launch
│   ├── providers/             Riverpod state
│   └── widgets/               Design-system components
│
└── main.dart

firestore.rules                The entire access-control layer
firestore.indexes.json         All 33 composite indexes, declared not discovered
```

Business logic lives in models, repositories and providers. Widgets render and
dispatch; they do not compute.

### Decisions worth knowing

**It runs on Firebase's free tier, and that shaped the architecture.** Cloud
Functions and Cloud Storage both require the paid plan, so this app uses neither.
What that meant in practice is worth reading before extending anything here.

**Money is integer minor units, never a double.** Binary floating point cannot
represent `0.10`, and the error accumulates across sums, splits and budget
comparisons. `Money` wraps an `int` of cents and all arithmetic goes through it.
This matters more under Firestore than under Postgres: there is no `numeric(16,2)`
to fall back on, so a monetary value stored as a number *is* a float. Amounts are
stored as an integer in a field suffixed `_minor`.

**Data is laid out so that ownership is structural.** Every document lives under
`users/{uid}/…`. The security rule is then one condition applied by prefix rather
than a `user_id == auth.uid` restated per collection, and a cross-user query has no
path to deny because no such path exists. A collection added under that tree
inherits the check by position — the opposite of the usual failure where a new table
is forgotten.

**Derived figures are written with the records that cause them.** A transaction, the
account balance it moves, the month's rollup and any affected budget are written in
one Firestore transaction: either all of it lands or none does. Every figure moves
with `FieldValue.increment`, which the server applies to whatever the current value
is, so two devices posting at once both count — a read-modify-write would make the
later write discard the earlier transaction.

The trade this makes against a server-side trigger is explicit. A Cloud Function
could be the *only* writer of a balance, with the rules refusing everyone else; here
the client must be allowed to write it, and no rule can check that an increment
matches the transaction that caused it. For a personal ledger that is bounded: the
only person who could falsify these figures is the account's owner, falsifying their
own records. What no one can do is touch another user's data, which the rules
enforce completely.

In exchange, **balances are immediate rather than eventually consistent** — the
figure on screen is never a second behind the ledger, which a trigger could not
promise.

**Multi-document writes are Firestore transactions.** Transfers write two linked
documents, splits write a set that must sum to the total, and confirming a candidate
writes a transaction and updates the candidate. All atomic from the client.

**Aggregates are maintained, not computed on demand.** Firestore bills per document
read and has no server-side `sum()`, and the free tier allows 50,000 reads a day. So
one rollup document per month is kept up to date as transactions are written; a
year of history costs twelve reads rather than several thousand. Where a rollup
cannot answer the question — a range that is not whole months, or a per-account
filter — the repository falls back to reading the transactions and says so, so the
UI can report "about" rather than a figure that disagrees with the list below it.

**Scheduled work runs on launch.** Recurring transactions, bill statuses and
subscription renewals are swept when a verified user signs in, rate-limited to once
every six hours. Nothing happens while the app is closed, so a transaction due on
the 1st posts when you next open the app — *dated the 1st*, so the ledger is still
correct. Every posted occurrence uses an id derived from the schedule and the date,
so running the sweep twice cannot double-post.

**Errors are mapped once.** `ErrorMapper` is the only code that knows what a
`FirebaseException` looks like. Nothing above it can leak a stack trace, an internal
code or a storage path into the UI.

## OCR

**Recognition runs on the device.** Google ML Kit reads the image locally, which
means there is no API key in the app, no key on a server, and nothing uploaded to be
read. The specification required that OCR credentials never ship in the client; the
honest way to honour that without a server is not to have a key at all.

Three things follow, all of them improvements over the cloud pipeline this replaced:

- **Receipts never leave the phone.** A bank statement is not sent anywhere to be
  read — a stronger privacy position than any signed URL.
- **It works offline**, which suits an app whose data already works offline.
- **It costs nothing**, with no quota to exhaust.

The recogniser sits behind an interface, so swapping it — or adding a cloud option
for scanned PDFs later — is one class:

```
startJob (pipeline)
    ↓
TextRecogniser
    └── MlKitTextRecogniser    images, on-device, free
```

**The limitation is real and stated in the UI.** ML Kit reads images, not PDFs. A
text-layer PDF — anything exported from online banking — is read directly without
any recogniser. A *scanned* PDF cannot be read on-device, and the app says so rather
than failing obscurely.

**Parsing is separate from recognition.** The recogniser's only job is text; the
parser's only job is interpretation. That split makes the parser testable against
fixed strings with no camera and no model, and it is why moving OCR from a cloud API
to the phone changed nothing in the parsers — the same 38 expectations that tested
the TypeScript version pass unchanged against the Dart.

Amounts are scored against their labels rather than taking the largest number on the
page, so `TOTAL 14,087.50` beats a `9,800.00` line item and a `SUB TOTAL` is actively
penalised. An ambiguous date like `03/04/2026` is returned with low confidence rather
than a silent guess, and the review screen flags it.

See [docs/ocr.md](docs/ocr.md) for the full pipeline.

---

## Security

- Every document under `users/{uid}/…`, so isolation is structural rather than
  conditional — a cross-user read has no path, not merely a denial
- A verified email address is required before any financial screen or document,
  because it is the only account-recovery path
- Raw OCR output is immutable, so a correction can never rewrite the evidence it was
  made against
- A candidate must be created unreviewed, and once it has produced a transaction
  that link cannot be cleared — the same receipt cannot be imported twice
- Amounts are required to be positive integers by the rules, which is what keeps a
  float out of a money field
- **Receipts and statements never leave the device.** They are not uploaded, not
  held by a third party, and not reachable by any URL
- **No OCR key exists** anywhere in the app or the project
- Session tokens in the platform keychain, not plain shared preferences
- Sign-out clears Firestore's persistent cache *and* the locally stored documents,
  so a shared device does not leak the previous user's records
- Account and card numbers: last four digits only. No passwords, no CVVs
- Uploads validated by magic number, not by file extension

What the rules **cannot** enforce without a server, stated plainly: that a balance
increment matches the transaction that caused it. See
[docs/security.md](docs/security.md) for the full picture, including what remains
possible.

---

## Getting started

```bash
git clone <repo> && cd Personal-Transaction-Manager
flutter pub get
flutter run
```

No `--dart-define`: there is nothing to supply at build time. The project details
come from `google-services.json` and the generated `firebase_options.dart`, and the
OCR key never leaves the server.

You need a Firebase project with the rules, indexes and functions deployed first,
and `android/app/google-services.json` in place — that file is gitignored, so a
fresh clone always needs it added.

**[MANUAL_SETUP.md](MANUAL_SETUP.md) walks through every step**, including the parts
that cannot be automated: creating the database, choosing its permanent region,
setting the OCR secret, deploying the functions, and a verification pass that checks
the product rule actually holds.

---

## Testing

```bash
flutter test                      # 225 unit, widget and parser tests
```

Unit tests concentrate on what a user would notice being wrong: that split lines
reconcile to the cent, that transfers cancel out, that a savings rate with no
income is zero rather than infinity, and that a monthly schedule on the 31st
lands on the 28th rather than rolling into March.

The parser tests run with no network, no API key and no database, which is the
point of keeping parsing separate from recognition. They also pin a contract across
languages: `Money.tryParse` in Dart and `parseAmountToken` in TypeScript must read
the same string to the same number, or a figure would change as it crossed the
boundary between the app and the pipeline.

The integration suite drives sign-in through to a saved transaction and asserts the
product guarantee directly against Firestore — including that a pending candidate
has created no transaction, that a confirmed one points at a transaction that
exists, and that reaching for another user's subtree is refused rather than quietly
returning nothing. It skips without credentials, so a fresh checkout stays green.

```bash
flutter test integration_test/app_flow_test.dart \
  --dart-define=TEST_USER_EMAIL=... \
  --dart-define=TEST_USER_PASSWORD=...
```

---

## Documentation

| Document | Contents |
|---|---|
| [MANUAL_SETUP.md](MANUAL_SETUP.md) | Step-by-step setup, start to finish |
| [docs/architecture.md](docs/architecture.md) | Layers, data flow, state management |
| [docs/database.md](docs/database.md) | Collections, documents, triggers, functions |
| [docs/indexes.md](docs/indexes.md) | Why each composite index exists |
| [docs/ocr.md](docs/ocr.md) | Pipeline, providers, parsing, confidence |
| [docs/storage.md](docs/storage.md) | Where documents live, and why on the device |
| [docs/security.md](docs/security.md) | Rules, threat model, what is unwritable |
| [docs/setup.md](docs/setup.md) | Local development and the emulator suite |
| [docs/deployment.md](docs/deployment.md) | Release builds and production checklist |

---

## Known limits

Stated plainly rather than left to be discovered.

**From the product**

- **Scanned PDFs need Azure.** Google Vision's synchronous endpoint does not
  accept PDFs, and synchronous Textract accepts one page. Text-layer PDFs work
  with any provider.
- **Notifications are in-app.** Budget alerts, bill reminders and import results
  appear in the notification centre, written by triggers and the scheduled
  function. OS-level push is not wired up; `docs/architecture.md` describes where
  it would attach.
- **No currency conversion.** An account holds one currency. Totals skip accounts
  in other currencies and say how many were left out, rather than converting at an
  invented rate.
- **PDFs are not rendered in-app.** The review screen shows a PDF's metadata and
  its extracted text; opening the file hands off to the platform viewer.

**From the free plan**

- **Receipt images do not sync between devices.** Sign in on a second phone and you
  see every transaction; the scans stay on the phone that made them. Uninstalling
  the app deletes them — the transactions survive.
- **Scheduled work happens on launch, not on a schedule.** A recurring transaction
  due on the 1st posts when you next open the app, dated the 1st. The ledger ends up
  identical; only the notification is late.
- **Derived figures are written by the client.** The rules cannot verify them. See
  the security notes above for why that is a bounded risk here and not a general one.
- **Scanned PDFs cannot be read.** On-device OCR reads images; text-layer PDFs work.

**From Firestore, and worth knowing before you extend this**

- **Search matches whole words.** There is no substring search and no `OR` across
  fields, so writes maintain an array of lowercased tokens, with prefixes for the
  merchant only. Typing `kee` finds `Keells`; typing `eells` does not.
- **Some filter combinations are applied on the client.** Firestore allows one
  `whereIn` per query and requires a range filter to lead the ordering. What can be
  indexed is sent; the rest is applied to what comes back, under a read ceiling. The
  result count then reports itself as approximate rather than showing a number that
  disagrees with the list.
- **Sorting by amount or merchant inside a date range reads a bounded window.**
  Firestore cannot express that ordering, so up to 2,000 documents are read and
  sorted in memory. The date filter is what keeps that from being hit.
- **Nothing cascades.** Deleting a document does not delete its subcollections, so
  the repositories walk them explicitly. An account holding transactions cannot be
  deleted at all — archiving is offered instead, because orphaned transactions would
  keep counting in the rollups while pointing at nothing.
- **50,000 reads a day** on the free tier. The rollups exist so that normal use is
  nowhere near it.

## Licence

Written as a portfolio project. Use it as you like.
