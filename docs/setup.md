# Local development

For the one-time Firebase console setup, see [MANUAL_SETUP.md](../MANUAL_SETUP.md).
This document covers working on the code day to day.

---

## Prerequisites

| Tool | Version | Why |
|---|---|---|
| Flutter | 3.35+ | Dart 3.9 language features: sealed classes, patterns, records |
| Node | 20 | Only for the Firebase CLI |
| Firebase CLI | 13+ | `npm install -g firebase-tools` |
| Java | 17 | Android builds, and the Firestore emulator |

```bash
flutter --version
node --version
firebase --version
java -version
```

---

## No environment variables

There is nothing to supply at build time.

```bash
flutter pub get
flutter run
```

The project details come from `android/app/google-services.json` and the generated
`lib/firebase_options.dart`. There is no OCR key to supply — ML Kit runs on the
device. `AppConfig` holds limits — upload size, PDF page count — and no credentials;
it exists so a build can be tightened without a code change:

```bash
flutter run --dart-define=MAX_UPLOAD_MB=5
```

`google-services.json` is gitignored, so a fresh clone needs it placed by hand —
MANUAL_SETUP step 4. The Gradle build fails without it, deliberately: an app that
silently could not reach the project would be harder to diagnose than a build that
stops.

---

## The emulator suite

The best thing about this backend for development. Firestore, Auth, Storage and
Functions, all local, with a UI, costing nothing.

```bash
cd functions && npm install && cd ..
firebase emulators:start
```

- UI: <http://localhost:4000>
- Firestore `8080`, Auth `9099`, Functions `5001`, Storage `9199`

### Pointing the app at it

In `main()`, after `FirebaseService.initialise()` and before `runApp`:

```dart
await FirebaseService.initialise();

if (const bool.fromEnvironment('USE_EMULATOR')) {
  FirebaseService.firestore.useFirestoreEmulator('localhost', 8080);
  await FirebaseService.auth.useAuthEmulator('localhost', 9099);
  FirebaseService.functions.useFunctionsEmulator('localhost', 5001);
  await FirebaseService.storage.useStorageEmulator('localhost', 9199);
}
```

```bash
flutter run --dart-define=USE_EMULATOR=true
```

On an Android emulator use `10.0.2.2` rather than `localhost`.

### Saving and reloading state

```bash
firebase emulators:start --export-on-exit=.emulator-data
firebase emulators:start --import=.emulator-data
```

Worth doing once you have a user with a few accounts and transactions. Rebuilding that
by hand after every restart is the main thing that makes people stop using the
emulator.

`.emulator-data` is not gitignored by name — add it if you keep one.

### What the emulator gets right, and what it does not

**Right:** rules are evaluated exactly as deployed, triggers fire, callables run,
indexes are not required.

**Not right:**

- **Indexes.** The emulator runs any query. A query that works locally can fail in
  production with `FAILED_PRECONDITION`. The composite indexes in
  `firestore.indexes.json` are the guard; add one whenever you add a query shape.
- **Timing.** Triggers fire almost instantly locally. In production a balance lags its
  transaction by a second or two, and the UI's handling of that is worth testing
  against the real project at least once.
- **Scheduled functions.** `dailyTasks` does not fire on a schedule in the emulator.
  Call its inner functions directly, or trigger it from Cloud Scheduler on the real
  project.
- **Storage and functions.** Neither is used, so neither emulator is started.

---

## Running things

```bash
flutter test                                    # 225 unit, widget and parser tests
flutter test test/core/parsing_test.dart        # the 38 parser cases alone
flutter analyze                                 # must be clean
flutter build apk --debug                       # a real compile, not just analysis
```

`flutter analyze` being clean is not the same as compiling. The analyzer misses things
the compiler catches, so `flutter build web` is worth running before a commit that
touches many files.

---

## Deploying pieces

```bash
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
```

That is the whole backend. There are no functions and no storage to deploy.

---

## Project layout

```
lib/
├── core/          config, constants, errors, routing, services, theme, utils
├── features/      one folder per feature, presentation only
├── shared/        models, repositories, providers, widgets
└── main.dart

firestore.rules  firestore.indexes.json  firebase.json
```

Where to put a change:

| Change | Goes in |
|---|---|
| A new screen | `features/<feature>/presentation/` |
| A calculation over models | `shared/models/calculations.dart` |
| A new query | the relevant repository, plus an index |
| New state | `shared/providers/` |
| A derived field | `ledger_writer.dart`, applied in the same Firestore transaction as the record |
| A multi-document write | a `runTransaction` in the relevant repository |
| A reusable widget | `shared/widgets/` |

A calculation that does no I/O belongs on the models, not the repositories. That is why
`calculations.dart` exists: a unit test of "do these balances add up" should not have
to import the data layer, and it used to, which meant arithmetic tests broke when the
backend changed.

---

## Adding a query

Four steps, in order, because missing the third is a production-only failure:

1. Write it in the repository.
2. Run it against the emulator.
3. **Add the composite index** to `firestore.indexes.json`, with a note in
   `docs/indexes.md`.
4. `firebase deploy --only firestore:indexes`.

Firestore needs a composite index for any query combining an equality filter with an
ordering, or using a range with a sort. Single-field indexes are automatic. The
emulator will not tell you — it runs anything.

## Adding a derived field

1. Add it to `LedgerWriter`, so it moves in the same Firestore transaction as the
   record it derives from. Nothing derived should be a second write that could fail
   on its own.
2. Use `FieldValue.increment`, never read-modify-write, so two devices posting at
   once both count rather than one discarding the other.
3. Apply the **difference** between the stored state and the new one, reading the
   stored document inside the transaction. An edit measured against a stale model
   makes the figure drift.
4. Add a rule for its *shape* — a positive int, the right owner. The rules cannot
   check that a derived value is arithmetically correct, so do not pretend otherwise
   in a comment.

---

## Conventions

- **Money is `Money`.** Never a `double`, never a bare `int` outside the class. The
  functions use `money.ts` for the same reason.
- **Field names are `snake_case`** in documents; callable arguments are `camelCase`.
- **Repositories throw `AppException`**, never a `FirebaseException`. `guard()` in
  `BaseRepository` handles the conversion; nothing above the data layer should know
  Firestore exists.
- **Four states per screen:** loading, empty, error, data. `state_views.dart` has the
  widgets.
- **Comments explain why.** The code says what it does.
