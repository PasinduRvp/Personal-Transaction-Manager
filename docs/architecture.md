# Architecture

## Layers

```
┌──────────────────────────────────────────────────────────────┐
│  Presentation          features/*/presentation/              │
│  Widgets render and dispatch. They do not compute.           │
└───────────────────────────┬──────────────────────────────────┘
                            │ watch / read
┌───────────────────────────▼──────────────────────────────────┐
│  State                 shared/providers/                     │
│  Riverpod. Orchestrates, caches, invalidates.                │
└───────────────────────────┬──────────────────────────────────┘
                            │ calls
┌───────────────────────────▼──────────────────────────────────┐
│  Data                  shared/repositories/                  │
│  The only layer that knows Firestore exists.                 │
└───────────────────────────┬──────────────────────────────────┘
                            │ maps to
┌───────────────────────────▼──────────────────────────────────┐
│  Domain                shared/models/                        │
│  Immutable. Rules live here or in a repository transaction.   │
└──────────────────────────────────────────────────────────────┘

core/  cuts across all four: theme, errors, services, utils, routing.
```

A dependency only ever points downward. A model knows nothing about a
repository; a repository knows nothing about a widget.

## Where logic lives

Three places, with a clear division:

**In the model** — anything derivable from the data itself. `Transaction.
signedAmount`, `BudgetProgress.remaining`, `SavingsGoal.
requiredMonthlyContribution`, `Bill.effectiveStatus`. These are pure functions of
their fields, and they are unit-tested without a database.

**In the repository, inside one Firestore transaction** — anything that must be
consistent across clients, that aggregates many documents, or that writes more than
one document at a time. Balances, budget spend, the monthly rollups, transfers,
splits, and the OCR confirm step.

Three reasons. Concurrent writes from two devices must both land, which means
`FieldValue.increment` applied by the server rather than a read-modify-write.
Aggregating a year of transactions on demand would mean reading — and paying for — a
year of transactions, so the rollups are maintained as the writes happen. And the
record and the figures derived from it must land together, which is what a Firestore
transaction gives: either all of it or none.

A Cloud Function would additionally make the client *unable* to write those figures
wrongly. That is the one thing this arrangement gives up, and
[security.md](security.md) says what it costs.

**In the provider** — orchestration only. Which reads to issue, in what order,
what to invalidate afterwards, and how to present failure. No arithmetic.

A worked example. "Is this budget exceeded?" is answered in three parts:

1. `LedgerWriter` moves `spent_minor` on the budget document by the difference, in
   the same Firestore transaction as the expense itself, with `FieldValue.increment`
   — so two devices posting at once both count rather than one overwriting the
   other's figure.
2. `BudgetProgress.isExceeded` compares two `Money` values, because that is a
   pure comparison.
3. `budgetsControllerProvider` decides when to re-ask, because that is a caching
   question.

## State management

Riverpod, with a deliberate split between reading and writing.

**Readers** are `AsyncNotifier`s or `FutureProvider`s keyed on the signed-in user:

```dart
class AccountsController extends AsyncNotifier<List<Account>> {
  @override
  Future<List<Account>> build() async {
    final userId = ref.watch(currentUserIdProvider);   // watch, not read
    if (userId == null) return const [];
    return ref.watch(accountRepositoryProvider).fetchAll();
  }
}
```

Watching `currentUserIdProvider` matters: signing into a different account on the
same device rebuilds every reader, so the previous user's data cannot linger on
screen for a frame.

**Writers** are separate, so a form can await one operation and show its own
progress without the list's paging state getting involved:

```dart
final transactionWriterProvider =
    AsyncNotifierProvider<TransactionWriter, void>(TransactionWriter.new);
```

### Optimistic updates

Applied where latency is felt and reverted on failure: theme switching,
preference toggles, swipe-to-delete, drag-to-reorder, and marking a notification
read. A switch that lags behind the finger feels broken; a switch that silently
fails is worse, so every optimistic path restores the previous value and surfaces
the error.

Not applied to anything that moves money. A transaction insert waits for the
server, because showing a balance that has not actually changed is the one thing
a finance app must not do.

### The dashboard

One provider assembling parallel reads rather than six independent providers:

```dart
final (accountList, monthSummary, previousSummary, recent, progress) = await (
  accountsRepo.fetchAll(),
  analytics.fetchCashflow(range: thisMonth, currency: currency),
  analytics.fetchCashflow(range: thisMonth.previousPeriod, ...),
  transactions.fetchRecent(limit: 8),
  budgets.fetchProgress(...),
).wait;
```

Record `.wait` rather than `Future.wait([...])`: the results stay typed, so a
reordering mistake is a compile error instead of a runtime cast. Six separate
providers would each flip to loading on their own schedule, which reads as the
dashboard flickering into place a piece at a time.

## Error handling

One sealed hierarchy, one mapper, and a rule: nothing above the repository layer
sees a `FirebaseException`.

```
Object thrown
    ↓  ErrorMapper.map()
AppException  (sealed)
    ├── NetworkException          "No internet connection…"
    ├── AuthenticationException   "Your session has expired…"
    ├── DatabaseException         "We could not save your changes…"
    ├── StorageException          "We could not upload your file…"
    ├── OcrException              + actionable suggestions per failure kind
    ├── ValidationException       + optional per-field errors
    ├── FileException
    ├── NotFoundException
    ├── PermissionException
    └── UnexpectedException
```

Each carries a `message` safe to display and a `debugDetail` that is logged and
never rendered. `ErrorMapper` is the only code that knows that Firestore's
`permission-denied` means a rule refused the write, or that `unavailable` is worth
retrying while `invalid-argument` is not.

Two codes are deliberately conflated. `FirebaseAuthException`'s
`invalid-credential`, `wrong-password`, `user-not-found` and `invalid-email` all
produce one message — "That email or password is incorrect" — because separate
messages would tell an attacker which addresses are registered.

Two are deliberately passed through. A callable's `invalid-argument` and
`failed-precondition` messages are shown as written, because the function is the
only thing that knows why a particular value was refused: "The splits are
Rs. 50.00 short of the Rs. 8,450.00 total" cannot be composed anywhere else.

`ErrorStateView` takes the raw error and maps it itself, so a screen that forgets
to map cannot leak anything.

## Routing

`GoRouter` with a single `redirect`. Authentication is decided in one place
rather than by each screen checking for itself — a missed check on one screen
would be a hole, and a central rule cannot be forgotten.

```dart
switch (auth.status) {
  case AuthStatus.unknown:              → hold on splash
  case AuthStatus.recoveringPassword:   → only the reset screen
  case AuthStatus.awaitingVerification: → only the verify screen
  case AuthStatus.unauthenticated:      → public routes only
  case AuthStatus.authenticated:        → everything except the auth screens
}
```

`AuthStatus` is one enum rather than a set of booleans, so the app cannot reach a
contradictory state like "authenticated but also recovering a password".

The five tabs use `StatefulShellRoute.indexedStack`, so each keeps its own
navigation stack and scroll position. Focused tasks — entering a transaction,
reviewing an import — are pushed onto the root navigator so they cover the tab
bar.

This is about not showing a broken empty screen, not about secrecy: the security
rules refuse the data regardless of what the client renders.

## Offline support

Read-through caching for what the app must still show with no connection: the
dashboard snapshot, accounts, categories, the profile and the first page of
transactions.

```dart
try {
  final rows = await client.from('accounts').select()...;
  await cache.writeJson(userId, CacheService.keyAccounts, rows);
  return rows.map(Account.fromJson).toList();
} on Object {
  final cached = cache.readList(userId, CacheService.keyAccounts);
  if (cached != null) return cached.value.map(Account.fromJson).toList();
  rethrow;                       // nothing cached: the error is the answer
}
```

Cache keys are namespaced per user id and cleared on sign-out, so a shared device
cannot surface the previous user's balances.

Writes are not queued. A transaction needs a connection. Queued offline writes
are listed as an extension point rather than half-implemented, because a sync
layer that silently drops or duplicates a financial record is worse than an
honest error message.

## Design system

Four token files, and a rule that no widget inlines a value:

| File | Holds |
|---|---|
| `app_colors.dart` | Brand, semantic and neutral colours; the chart palette; `AppPalette` theme extension |
| `app_typography.dart` | Type scale, plus money styles with tabular figures so columns of digits align |
| `app_spacing.dart` | 4pt scale, radii, elevation |
| `app_theme.dart` | Assembles light and dark `ThemeData` |

Semantic colours are reached through `context.palette`, which resolves the
`AppPalette` extension, so income is the same green on every screen in both
themes. Colour carries meaning in this app — income green, expense red, transfers
blue — and the widget tests assert it, because a figure in the wrong colour reads
as a wrong number.

## Extension points

Designed so these attach without a rewrite:

**OS-level notifications.** Genuinely blocked on the free tier: push needs a server
to send from, and Cloud Functions require the paid plan. The notification centre
works in-app, written when the maintenance sweep runs. Adding push later means a
device-token field and a function — nothing in the app's data flow changes.

**Offline writes.** Already present, and not something that had to be built:
Firestore queues writes made while offline and replays them on reconnection. The
limitation is that a *callable* cannot be queued — a transfer or an OCR confirm
needs a connection, because those are server-side decisions rather than document
writes. The UI reports that rather than appearing to succeed.

**A fourth OCR provider.** One class implementing `OcrProvider`, one case in
`resolveProvider()`. Nothing downstream names a vendor.

**Item-level receipt extraction.** The `results` subcollection keeps the raw text
immutably, so a line-item parser can be run over documents already imported without
re-reading a single file.

**AI features.** None are present, by design. The data model supports them: the
stored raw text for categorisation, the monthly rollups for forecasting, the
transactions for insight. On-device inference would fit the current architecture
exactly, with the same rule that governs OCR — a suggestion is reviewed before it
becomes a record.
