# Data model

Finora's data lives in Firestore. This document describes the layout, what each
collection holds, which fields are derived, and what replaced the Postgres features
Firestore does not have.

---

## The shape

Everything belongs to one user, and is stored under that user.

```
users/{uid}                                    profile
├── settings/app                               preferences
├── bootstrap/init                             write-only seeding marker
├── accounts/{id}
├── categories/{id}
├── transactions/{id}
│   └── splits/{id}
├── budgets/{id}
├── savingsGoals/{id}
│   └── contributions/{id}
├── bills/{id}
├── subscriptions/{id}
├── recurringTransactions/{id}
├── documents/{id}
├── ocrJobs/{id}
│   └── results/{pageNumber}
├── ocrCandidates/{id}
├── notifications/{id}
└── monthlySummaries/{YYYY-MM}
```

### Why subcollections rather than a flat layout

A flat layout — a top-level `transactions` collection with a `user_id` field — is
the more common Firestore arrangement, and it was rejected deliberately.

Under this layout the security rule is **one condition applied by prefix**:

```
match /users/{uid}/{document=**} { ... request.auth.uid == uid ... }
```

A collection added under that tree inherits the check by position. Under a flat
layout each new collection needs its own `where user_id == auth.uid` rule, and the
failure mode is a new collection shipped without one — which is the same failure
mode as a new Postgres table shipped without an RLS policy, and the one that
arrangement was chosen to avoid.

It is also a stronger guarantee. A flat layout lets a client *construct* a query for
another user's documents, which the rules then deny. Here there is no path to
construct: `users/{someoneElse}/transactions` is a path the rules reject outright,
and the integration test asserts that it raises `permission-denied` rather than
returning an empty list.

The cost is that cross-user queries need a collection group, which only the
scheduled function and one client query use. Both are listed in
`firestore.indexes.json` with `COLLECTION_GROUP` scope, and the rules for them
require the `user_id` filter rather than assuming it.

### Field naming

Field names are `snake_case`, not the `camelCase` more common in Firestore. They
match the Dart models and this documentation; renaming several
hundred string literals across three languages would be a large mechanical change
with nothing to show for it. Consistency across the three mattered more than
matching a convention.

Callable function *arguments* are `camelCase`, because those are JSON payloads
written and read in one place each.

---

## Money

**Every monetary value is an integer count of minor units, in a field suffixed
`_minor`, with a sibling `currency`.**

`845000` + `LKR` is `Rs. 8,450.00`.

This is not a stylistic choice. Firestore has no decimal type — a number is an
IEEE-754 double — so a monetary value stored as a number *is* a float, and
`0.1 + 0.2 !== 0.3` in Dart and JavaScript alike. The Postgres build had
`numeric(16,2)` as a backstop; here there is none, so the integer representation is
the only thing standing between the app and a budget that drifts by cents across a
hundred expenses.

Integers are exact in a double up to 2^53, which is about 90 trillion rupees.

The suffix exists so that nobody reading the Firestore console mistakes `845000` for
rupees. Both `Money` in Dart and `money.ts` in the functions enforce the conversion;
`minorKey('amount')` is the single definition of the field name in each.

### Calendar dates versus instants

- A **date** — a bill's due date, a budget's period bound, a contribution's date —
  is stored as a `yyyy-MM-dd` **string**. It sorts and compares lexicographically in
  a `where` clause, and it cannot shift a day when the device changes time zone. A
  bill due on the 1st must not read as due on the 31st because someone flew east.
- An **instant** — when a transaction happened, when a record was created — is a
  `Timestamp`.
- `created_at` and `updated_at` are always `FieldValue.serverTimestamp()`. A device
  clock can be wrong by hours, and a transaction list ordered by a client-set time
  would be wrong with it.

---

## Collections

### `users/{uid}` — profile

`email`, `full_name`, `profile_image_url` (a storage path, not a URL),
`default_currency`, `timezone`, `language`, `theme`, `seeded_at`.

Created by `onUserDocumentRequested`, never by the client. `seeded_at` marks the
account as initialised and the rules forbid clearing it — a client that could would
make the seeding run again and duplicate every category.

### `settings/app`

The notification switches, `biometric_lock_enabled`, `default_account_id`,
`hide_amounts_on_dashboard`, `week_starts_monday`.

Kept in its own document rather than as fields on the profile: the profile is read on
nearly every screen, and a settings toggle should not invalidate the snapshot every
listener is watching.

### `bootstrap/init`

A one-field marker the app writes after sign-in. Its creation triggers account
seeding. Write-only — the client never reads it back.

This exists because Firebase has no "after user created" Firestore trigger. A
blocking `beforeUserCreated` function cannot write documents for a user that does not
exist yet, and seeding from the app would mean two devices signing in at once each
deciding the data was missing and each writing a full set of categories. A marker at
a fixed id is idempotent, the trigger fires only on first create, and the app can
therefore write it on every sign-in — which also repairs a sign-up whose seeding never
ran.

### `accounts/{id}`

`name`, `type`, `currency`, `initial_balance_minor`, `current_balance_minor`,
`institution_name`, `account_number_last4`, `credit_limit_minor`, `icon`, `color`,
`is_active`, `is_archived`, `sort_order`.

**`current_balance_minor` is derived.** On create the rules require it to equal
`initial_balance_minor` — which is why a new account shows its opening balance
immediately rather than flashing zero. After that it is moved only by `LedgerWriter`,
with `FieldValue.increment`, in the same Firestore transaction as the transaction
that caused the change — so the balance and the ledger cannot disagree, and two
devices posting at once both count.

Correcting the opening balance changes both fields by the same amount, which keeps
the transactions already posted on top intact.

Only the last four digits of an account number are ever stored. A full account or
card number must never reach the database.

### `categories/{id}`

`name`, `kind` (`EXPENSE` | `INCOME`), `icon`, `color`, `is_system`, `is_archived`,
`sort_order`.

22 are written at sign-up. `is_system` marks them, the rules forbid a client claiming
it, and a system category may be archived but never deleted — a transaction from two
years ago still points at one.

A non-system category can be deleted only when nothing references it. The repository
counts transactions *and* split lines first, the latter through a collection-group
query. Firestore enforces no referential integrity at all, so that check is the only
thing between a delete and a reporting slice that quietly vanishes.

### `transactions/{id}`

`account_id`, `category_id`, `type`, `amount_minor`, `currency`, `description`,
`merchant`, `payment_method`, `transaction_date`, `notes`, `document_id`, `source`,
`status`, `reference_number`, `is_split`, `search_terms`, and for transfers
`transfer_group_id`, `transfer_direction`, `transfer_peer_account_id`.

`amount_minor` is **always positive**. The sign is derived from `type`, and for a
transfer from `transfer_direction` — so a document cannot contradict itself by being
a negative expense. `signedMinorUnits()` is the one definition, in `money.ts`.

A **transfer** is two documents sharing a `transfer_group_id`, one `OUT` and one `IN`,
each naming the other's account so a list row can say "to Savings" without a second
read. The rules forbid a client creating or editing one: half a transfer destroys
money.

`applied_signed_minor` records what the balance trigger last applied for this
document. It is the idempotence key — Firestore triggers are at-least-once, and
without it a redelivery would double a balance. The rules forbid a client writing it,
because a client that could set it could make the trigger apply a delta of its
choosing.

`search_terms` is an array of lowercased tokens from the merchant, description, notes
and reference, plus prefixes of the merchant. See **Text search** below.

#### `splits/{id}`

`amount_minor`, `currency`, `category_id`, `description`, `sort_order`.

**Written only by `replaceTransactionSplits`.** Postgres enforced "the splits sum to
the transaction total" with a deferred constraint trigger; Firestore has nothing
equivalent, so that function is the constraint, and it only works because the rules
give the client no write to this subcollection at all.

### `budgets/{id}`

`category_id` (null means every expense category), `name`, `amount_minor`, `period`,
`start_date`, `end_date`, `alert_threshold`, `rollover`, `is_archived`, and the
derived `spent_minor` + `spent_period_start`.

`spent_minor` belongs to **one period**, recorded alongside it. When the period rolls
over, the stored figure is last period's, and the client reads it as zero rather than
carrying it forward — which self-heals on the first transaction of the new period,
because a figure stamped with an older period start is replaced rather than
incremented. Both fields are unwritable by the client: one that could write them
could show itself under budget.

### `savingsGoals/{id}`

`name`, `target_amount_minor`, `current_amount_minor`, `currency`, `target_date`,
`account_id`, `is_completed`, `is_archived`.

`current_amount_minor` is the sum of the contributions, applied by
`onContributionWritten` with an increment. `is_completed` stays writable — it is the
user's judgement, not a derived figure. A goal that closed itself on reaching its
target would stop accepting contributions the user is still making, so reaching the
target raises a notification and nothing more.

#### `contributions/{id}`

`amount_minor` (negative for a withdrawal), `currency`, `occurred_on`, `note`,
`account_id`, `transfer_group_id`.

Created only by `contributeToGoal`, which also writes both legs of a transfer when the
deposit is funded from an account — four documents that must succeed together, or the
goal would claim money the accounts never gave up. Deleting one *is* allowed: the
trigger adjusts the total, and correcting a mistaken deposit should not need a
function call.

### `bills`, `subscriptions`, `recurringTransactions`

Bills carry `name`, `payee`, `amount_minor`, `due_date`, `status`, `recurrence`,
`category_id`, `account_id`, `paid_transaction_id`.

Marking a bill paid goes through `markBillPaid`, and the rules specifically forbid a
client setting `status` to `PAID` or writing `paid_transaction_id`. A bill marked paid
with no transaction behind it would leave the balance wrong with nothing on screen to
explain why. A recurring bill advances to its next due date in the same write, so the
next instance is visible the moment this one is paid.

`status` is a stored field rather than something the client infers from the date,
because Firestore cannot filter on a computed value — the scheduled function moves
overdue bills to `OVERDUE`.

Subscriptions roll forward on renewal **without posting a transaction**. Whether the
card was actually charged is something the user's statement says, not something this
can assume; inventing the expense would take money out of an account that may not
have lost it.

`recurringTransactions` carries `last_executed_on`, which the client may not rewind —
that would make the schedule post the same months again.

### `documents/{id}`

`file_name`, `storage_path` (the full object path), `mime_type`, `file_size`,
`page_count`, `document_type`, `ocr_status`, `checksum`, `is_archived`.

There is one bucket, so the folder is part of `storage_path` rather than a separate
field. `checksum` is the SHA-256 of the uploaded bytes, which is how a re-upload of
the same receipt is spotted before it becomes a duplicate transaction.

`ocr_status` belongs to the pipeline — it is the only thing that knows how the read
went — and the rules forbid a client writing it, along with `checksum`,
`storage_path` and `file_size`.

Deleting a document clears the attachment from any transaction that referenced it,
removes its jobs and unconfirmed candidates, and deletes the file. A receipt is
evidence for a transaction, not the transaction itself; deleting a photo must never
delete a record of spending.

### `ocrJobs/{id}` and `results/{pageNumber}`

The job records `status`, `provider`, `page_count`, `pages_processed`,
`used_embedded_text`, `candidate_count`, `error_code`, `error_message`, and the
timestamps.

**Entirely unwritable by the client.** Every transition — `PROCESSING`, `COMPLETED`,
`FAILED`, `CANCELLED` — is a claim about what the server did, and a client that could
write one could claim a document had been read when it had not.

`results` holds the provider's unmodified text, one document per page, with its
confidence and metadata. Immutable even to the pipeline once written: a correction on
the review screen must never be able to rewrite the evidence the correction was made
against. It is also excluded from indexing — it is read by id, and indexing it would
cost an index entry per term on every page of every statement for a query nobody
makes.

### `ocrCandidates/{id}`

What the parser proposed: `transaction_type`, `amount_minor` (**nullable on
purpose**), `currency`, `merchant`, `description`, `transaction_date`,
`suggested_category_id`, `payment_method`, `reference_number`, `confidence`,
`field_confidence`, `page_number`, `raw_line`, `sort_order`, plus `status`,
`created_transaction_id` and `duplicate_of_transaction_id`.

`amount_minor` is null when the parser could not find one, and is left null rather
than defaulted to zero: the review screen requires the user to supply it, and a zero
would look like a figure that had been read.

`account_id` is always null when a candidate is created. A document does not say which
of the user's accounts it belongs to, and guessing would put money in the wrong place.

Candidates sit at the top level rather than under their job, because the dashboard
counts every pending candidate across all imports — a subcollection would make that a
collection-group query.

**The user may edit a candidate** — that is the entire point of the review step. What
they may not touch:

| Field | Why |
|---|---|
| `status`, `created_transaction_id`, `confirmed_at` | Written only by `confirmOcrCandidate`, atomically with the transaction. That pair is what guarantees a confirmed candidate points at a transaction that exists. |
| `confidence`, `field_confidence` | What the parser reported. A client that could raise them could make an uncertain figure look verified on screen. |
| `job_id`, `document_id`, `raw_line`, `page_number` | The tie to the evidence. |
| `duplicate_of_transaction_id` | The pipeline's own advisory finding. |

A candidate is never deleted by the client. One the user does not want is dismissed
through `ignoreOcrCandidate`, which keeps the record of what was proposed — so
re-reading the same statement does not offer it again.

### `notifications/{id}`

`kind`, `title`, `body`, `related_type`, `related_id`, `is_read`, `read_at`.

**Create is denied to the client.** An alert saying "budget exceeded" should be the
server's judgement, not something a client can fabricate. Update is narrowed to
`is_read` and `read_at` only; delete is allowed.

The document **id is derived** from what the notification is about — 
`{budgetId}_{YYYY-MM}_BUDGET_EXCEEDED`, `bill_{billId}_{dueDate}`,
`ocr_{jobId}_completed`. A `create` on an id that exists is refused, which is exactly
the once-per-period guard wanted: the second transaction that is also over budget does
not produce a second alert.

### `monthlySummaries/{YYYY-MM}`

The maintained rollups, and the reason the analytics screens are cheap.

```
month, currency, transaction_count,
income_minor, expenses_minor,
by_day:            { "15": { income_minor, expenses_minor } }
by_category:       { "<categoryId>": { expense_minor, income_minor, count } }
by_payment_method: { "CARD": { total_minor, count } }
by_merchant:       { "<key>": { name, total_minor, count, last_date } }
largest_expense:   { transaction_id, amount_minor, currency, merchant, date }
```

The id is the month, so the collection sorts chronologically and a year is one
`whereIn` query rather than twelve.

**Entirely unwritable by the client.** Every figure is derived from the transactions,
and a client that could write them could show itself any history it liked.

The nested maps are excluded from indexing: they hold a key per category, per merchant
and per day, so leaving them indexed would mean hundreds of index entries per month
per user, written on every transaction, for queries that do not exist.

`by_merchant` is capped at 200 keys. Past that the trigger stops adding new ones, so a
month of unique merchants cannot grow the document towards Firestore's 1 MB limit; the
chart shows ten.

`largest_expense` is a maximum, not a sum, so it cannot be an increment. It is
replaced only when a new expense beats the stored one, which means deleting the
record-holder leaves a stale id — the client reads the transaction by id and shows
nothing if it is gone. Recomputing the true maximum on every delete would mean
scanning the month, which is the cost the rollups exist to avoid.

---

## What replaced each Postgres feature

This project has had three backends. The column that matters is the last one.

| Postgres | Firebase, free tier | Where |
|---|---|---|
| Row Level Security | Path-prefixed rules under `users/{uid}` | `firestore.rules` |
| Column-level grants | Partly: shape and immutability rules. Derived *values* are not protected — see below. | `firestore.rules` |
| Row trigger inside the write | `LedgerWriter`, inside the same client Firestore transaction | `ledger_writer.dart` |
| Deferred constraint trigger | A check inside `replaceSplits`, before the transaction commits | `transaction_repository.dart` |
| `check (status <> 'CONFIRMED' or created_transaction_id is not null)` | One Firestore transaction writing both, plus a rule that the link cannot be cleared | `ocr_repository.dart` |
| `numeric(16,2)` | Integer minor units, with the rules requiring an `int` | `money.dart` |
| Foreign keys | Nothing. Checks are explicit in the repositories. | — |
| `on delete cascade` | Nothing. Subcollections are walked explicitly. | `profile_repository.dart` |
| SQL aggregate functions | Maintained rollup documents | `monthlySummaries` |
| `pg_trgm` similarity | Dice coefficient over bigrams | `transaction_repository.dart` |
| Trigram text search | `search_terms` token array | below |
| `pg_cron` | A sweep when the app opens, rate-limited to six-hourly | `maintenance_runner.dart` |
| Offset paging (`range`) | Cursor paging (`startAfterDocument`) | `transaction_repository.dart` |
| Server-side seeding | An idempotent client transaction guarded by `seeded_at` | `account_seeder.dart` |

### The consistency difference, stated plainly

A Postgres trigger ran inside the same transaction as the insert, so a balance could
not lag its ledger by even a moment.

**This arrangement has the same property**, because the ledger arithmetic runs in the
same Firestore transaction as the document write. That is one respect in which the
free tier behaves better than Cloud Functions would: a trigger runs *after* the write
succeeds, so a balance is eventually consistent, typically a second or two behind.
Here it is never behind.

What is guaranteed:

- **Atomicity.** The transaction, the balance, the rollup and any affected budget land
  together or not at all.
- **Concurrency.** Every derived figure moves with `FieldValue.increment`, applied by
  the server to whatever the current value is, so two devices posting at once both
  count.
- **Correction by difference.** An edit reads the stored document inside the
  transaction and applies the *difference*, so a stale model on the client cannot make
  a balance drift.

What is **not** guaranteed, and could be by a server: that the increment matches the
transaction that caused it. Firestore rules see one write in isolation and cannot
compare across documents. See [security.md](security.md) for why that is a bounded
risk for a personal ledger.

## Text search

Firestore has no text search and cannot `OR` across fields, so "find transactions
mentioning Keells" is not expressible as a query over `merchant`, `description` and
`notes`.

Writes flatten those fields into `search_terms`: lowercased tokens of two characters
or more, deduplicated, capped at 80. Tokens from the **merchant** also contribute
their prefixes from two characters up to twelve, so typing `kee` finds `Keells`.

Querying is one `array-contains` — a single indexed lookup regardless of how much
history there is. A multi-word search sends the first token and filters the rest on
the returned page.

The limitation is real and documented rather than hidden: **a whole word has to be
typed** for anything other than the merchant. `eells` does not find `Keells`.
Generating every substring would multiply the index entries for little benefit, and
the honest alternative is a search service, which this project does not use.

`searchTerms()` exists twice — `json_map.dart` and `guard.ts` — because both the
client and the functions create transactions. A transaction created by a function
without these terms would be invisible to search, a bug that would surface days later
when someone looked for a bill they had paid.

---

## Indexes

All 33 composite indexes are declared in `firestore.indexes.json`, with the reason
for each in [indexes.md](indexes.md). Single-field indexes are automatic.

Declaring them matters: a missing index in Firestore is a runtime failure on a screen
the user has already opened, and the error carries a creation link that only ever
appears in a log the user cannot see.
