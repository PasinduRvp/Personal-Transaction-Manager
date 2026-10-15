# Firestore indexes

Why each composite index in `firestore.indexes.json` exists.

The file itself holds no comments: the Firebase CLI validates it against the
Firestore API's schema and rejects keys it does not recognise, so the reasoning
lives here instead.

A missing index in Firestore is a runtime failure on a screen the user has
already opened, and the error carries a creation link that only ever appears in
a log they cannot see. Declaring them up front is what makes a fresh deploy work
the first time.

Single-field indexes are automatic and are not listed. What is listed is every
combination of an equality filter with an ordering, every range paired with a
sort, and every collection-group query. `__name__` is appended implicitly as the
final tie-breaker, which is what makes cursor paging stable when several
transactions share a timestamp.

## `accounts`

`is_archived ASCENDING, sort_order ASCENDING, created_at ASCENDING`

Accounts list: active first, then the user's own ordering.

## `categories`

`kind ASCENDING, sort_order ASCENDING, name ASCENDING`

Categories grouped by kind, then by the user's ordering.

## `transactions`

`search_terms CONTAINS, transaction_date DESCENDING`

Free-text search: one token against the stored term array, newest first.

## `transactions`

`category_id ASCENDING, transaction_date DESCENDING`

Filter by category, account or type, ordered by date. Both directions, because the list sorts oldest-first too.

## `transactions`

`document_id ASCENDING, transaction_date DESCENDING`

Transactions attached to one document, for the review screen's 'already imported' state.

## `transactions`

`transfer_group_id ASCENDING, transfer_direction ASCENDING`

Both legs of a transfer, OUT before IN.

## `transactions`

`amount_minor ASCENDING, transaction_date ASCENDING`

Duplicate detection: the same amount within a few days.

## `budgets`

`is_archived ASCENDING, created_at ASCENDING`

Budgets, unarchived, oldest first.

## `savingsGoals`

`is_archived ASCENDING, is_completed ASCENDING, created_at ASCENDING`

Savings goals: unfinished first.

## `contributions`

`occurred_on DESCENDING, created_at DESCENDING`

A goal's contribution ledger, newest first.

## `bills`

`is_archived ASCENDING, due_date ASCENDING`

Bills by due date.

## `bills`

`is_archived ASCENDING, status ASCENDING, due_date ASCENDING`

The dashboard's upcoming list: unpaid or overdue, due soon.

## `subscriptions`

`is_archived ASCENDING, is_active DESCENDING, next_renewal_date ASCENDING`

Subscriptions: active first, then by renewal date.

## `recurringTransactions`

`is_active DESCENDING, next_execution_date ASCENDING`

Recurring schedules: active first, then by next execution.

## `documents`

`is_archived ASCENDING, created_at DESCENDING`

Documents, newest first.

## `documents`

`checksum ASCENDING, is_archived ASCENDING, created_at DESCENDING`

Re-upload detection by content hash.

## `ocrJobs`

`document_id ASCENDING, created_at DESCENDING`

The latest job for a document, and the check for an existing completed read.

## `ocrCandidates`

`job_id ASCENDING, sort_order ASCENDING, created_at ASCENDING`

A job's candidates, in the order the parser found them.

## `ocrCandidates`

`job_id ASCENDING, status ASCENDING, sort_order ASCENDING, created_at ASCENDING`

A job's candidates still awaiting review.

## `ocrCandidates`

`document_id ASCENDING, status ASCENDING`

Candidates attached to a document, used when the document is deleted.

## `notifications`

`is_read ASCENDING, created_at DESCENDING`

Notification centre, and the housekeeping sweep.

## `splits`

`user_id ASCENDING, category_id ASCENDING`

COLLECTION_GROUP scope below. These span every user's subcollections and are used by the daily scheduled function, which has no single user to scope to, and by the client's count of split lines referencing a category.

## `results`

`raw_text`

Raw OCR text is never queried — it is read by document id for the 'what we read' panel. Indexing it would cost an index entry per term on every page of every statement, for a query nobody makes.  `field_confidence` and `metadata` are maps read whole for the same reason.

## `monthlySummaries`

`by_category`

The rollups are read by document id — the month is the id — and never filtered. Their nested maps hold a key per category, per merchant and per day, so leaving them indexed would mean hundreds of index entries per month per user, written on every transaction, for queries that do not exist.

## `transactions`

`notes`

Notes and descriptions are searched through `search_terms`, not directly, so their own indexes earn nothing.

## ``



Composite indexes for every query the app and the functions run.  Declared here rather than created from the console's error link. A missing index in Firestore is a runtime failure on a screen the user has already opened, and the link in that error only ever appears in a log the user cannot see — so a fresh deploy that works first time means writing these down.  Single-field indexes are automatic and are not listed: a query filtering or ordering on one field needs nothing here. What is listed is every combination of an equality filter with an ordering, every range paired with a sort, and every collection-group query the scheduled function makes.  `__name__` is appended implicitly as the final tie-breaker, which is what makes cursor paging stable when several transactions share a timestamp.

