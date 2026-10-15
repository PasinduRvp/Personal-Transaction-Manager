# Manual setup

Everything that cannot be done from the repository: the Firebase console settings
and the one deploy.

Project `finora-transaction-manager`, Android package `com.finora.finora`.

**This runs entirely on Firebase's free Spark plan.** No card, no billing account,
no Blaze. About 15 minutes.

Commands are PowerShell, run from the repository root:

```powershell
cd "C:\Users\Pasindu\OneDrive - Sri Lanka Institute of Information Technology\Desktop\My Projects\Personal Transaction Manager\Personal-Transaction-Manager"
```

---

## What the free plan means for this app

Two Firebase features require the paid Blaze plan, and the app is built not to need
either.

| | How it works here |
|---|---|
| **Cloud Functions** | Not used. Every derived figure — balances, budget spend, savings totals — is written by the app, inside the same Firestore transaction as the record it derives from. |
| **Cloud Storage** | Not used. Receipts and statements are stored **on the device**. |
| **OCR** | Runs **on the device** with Google ML Kit. No API key exists anywhere, nothing is uploaded to be read, nothing is billed. |
| **Scheduled jobs** | Run when the app opens, rate-limited to once every six hours. |

What this costs, stated up front rather than left to be discovered:

- **Receipt images do not sync between devices.** Sign in on a second phone and you
  see every transaction; the scans themselves stay on the phone that made them.
  Uninstalling the app deletes them. The transactions survive.
- **Scheduled work happens on launch, not on a schedule.** A recurring transaction
  due on the 1st posts the next time you open the app — dated the 1st, so the ledger
  is still right. Only the notification is late.
- **Derived figures are written by the app, not by a server.** The rules cannot
  check that a balance increment matches the transaction that caused it, so a
  modified client could write a wrong balance. For a personal ledger the only person
  who could do that is you, to your own records. The rules still make it impossible
  for anyone to read or write *another user's* data, which is the part that matters.

OCR is actually **better** on this plan: receipts are never uploaded anywhere, it
works offline, and there is no key to leak.

---

# Part 1 — Firebase console

## 1. Create the Firestore database

**This is the one decision you cannot change later.** The region is permanent for
the life of the project.

1. <https://console.firebase.google.com> → **finora-transaction-manager**
2. **Build → Firestore Database → Create database**
3. **Production mode**, not test mode. Step 5 deploys the real rules.
   *(If you already created it in test mode, that is fine — step 5 replaces those
   rules. Do not leave test mode in place: it allows anyone on the internet to read
   and write your entire database until it expires.)*
4. Region: **asia-south1 (Mumbai)**, closest to Sri Lanka
5. **Enable**

## 2. Enable Authentication

1. **Build → Authentication → Get started**
2. **Sign-in method → Email/Password → Enable**
3. Leave **Email link (passwordless sign-in)** off — the app does not use it
4. **Save**

Then **Authentication → Settings → User actions**: confirm **Email enumeration
protection** is on.

That stops the sign-in and reset endpoints revealing whether an address is
registered, and the app matches it — `ErrorMapper` returns one joint message for
wrong-password and no-such-user alike, and the forgot-password screen always reports
success.

### Email templates

The app requires a verified address before showing any financial screen, because
password recovery is the only route back into an account.

**Authentication → Templates** → review **Email address verification** and **Password
reset**, and set the **From** name to `Finora`. A verification email that lands in
spam locks the user out of their own data, so for real use add a custom domain under
**Templates → Customise domain**.

> **Do not enable Storage.** The app does not use it, and on a project created after
> October 2024 it would ask you to upgrade to Blaze.

## 3. Place `google-services.json`

Already done — the file is at `android/app/google-services.json` and the Android
build has been verified against it.

If you ever need it again: **Project settings → Your apps → Android app →
google-services.json**, saved to exactly `android/app/google-services.json`. It is
gitignored, so a fresh clone always needs it placed by hand, and the Gradle build
fails without it — deliberately, because an app that silently could not reach the
project would be harder to diagnose.

### About the API key

It is not a secret in Firebase's model: it identifies the project, and what anyone
can actually *do* is decided by the security rules and the caller's ID token.
Possessing it grants no access to your data.

It can still be used to call your project's own auth endpoints — enough to create
junk accounts and burn quota. So restrict it: **Google Cloud Console → APIs &
Services → Credentials** → open the Android key → **API restrictions** → limit it to
**Identity Toolkit** and **Cloud Firestore**. Those are the only two APIs this app
uses.

You pasted the key into a chat twice. That is not an emergency for the reason above,
but to rotate it: create a new Android key in Cloud Console with the same
restrictions, delete the old one, download a fresh `google-services.json`.

## 4. Install the Firebase CLI

```powershell
npm install -g firebase-tools
firebase login
firebase projects:list
```

`finora-transaction-manager` must appear.

---

# Part 2 — deploy

There is exactly one deploy, and it is free.

## 5. Deploy the rules and indexes

```powershell
firebase deploy --only firestore:rules,firestore:indexes
```

That is the whole backend deployment. No functions, no storage, no build step.

**Read `firestore.rules` once before deploying.** It is the entire access-control
layer — there is no server between the app and the database, so what the rules allow
is what is possible. The parts worth understanding:

- Every document lives under `users/{uid}/…`, so ownership is one condition applied
  by prefix. A cross-user path is rejected outright rather than returning an empty
  result, and a collection added under that tree inherits the check by position.
- A **verified email** is required before any financial data is reachable.
- Raw OCR output is immutable, so a correction on the review screen can never
  rewrite the evidence it was made against.
- A candidate must be created **unreviewed**, and once it has produced a transaction
  that link cannot be cleared — so the same receipt cannot be imported twice.
- Amounts must be positive integers, which is what keeps a float out of a money
  field.

The 33 composite indexes are declared in `firestore.indexes.json`, with the reason
for each in `docs/indexes.md`. Building them on an empty database is instant.

## 6. Run the app

```powershell
flutter pub get
flutter run
```

No `--dart-define`, no secrets, nothing else to configure.

The first OCR import downloads ML Kit's text model through Google Play Services —
a few megabytes, once, automatically. On a device without Play Services the import
reports that clearly instead of failing obscurely.

---

# Part 3 — verify

Work through this in order; each step depends on the last.

### Sign up

Register with a real address. You should land on **Confirm your email**, not the
dashboard — a verified address is required before any financial screen.

Click the emailed link and come back. The app notices within a few seconds.

**Then check Firestore.** You should see `users/{uid}` with your name and currency,
`users/{uid}/settings/app`, and **22 documents** under `users/{uid}/categories`.
Those are written by the app's seeder inside a single Firestore transaction, so two
devices signing in at once cannot both write them.

If they are missing, sign out and back in — seeding runs on every sign-in and is
idempotent.

### Create an account, add a transaction

Add a cash account with an opening balance of 10,000. The list should show
Rs. 10,000.00 immediately.

Add an expense of 2,500. The balance should become Rs. 7,500.00 — **immediately**,
with no delay. The transaction and the balance change are written in one Firestore
transaction, which is the one respect in which the free plan behaves better than the
paid one.

Then delete that transaction. The balance must go back to Rs. 10,000.00 exactly.

### Create a budget

Make a monthly budget of 5,000 on the category you just spent under. It should show
50% used.

### Import a receipt — the headline feature

1. **Documents → Upload**, choose a photo of a receipt
2. ML Kit reads it on the device, usually in under a second
3. You land on the **review screen**

Check, deliberately:

- **No transaction exists yet.** Open the transactions list. Nothing there. The
  extraction produced a *candidate*, and a candidate is not a transaction.
- The amount, date and merchant are shown with confidence indicators, and anything
  uncertain is flagged.
- **The account field is empty and required.** A document does not say which of your
  accounts it belongs to, so the parser never guesses.
- Change the amount deliberately.
- Press **Confirm**. *Now* the transaction appears — with your corrected figure, and
  the balance moves to match.

Then check the candidate in Firestore: it still holds what the parser originally
read, with `status: CONFIRMED` and `created_transaction_id` pointing at the new
transaction. Both are written in one Firestore transaction, so a confirmed candidate
can never point at a transaction that does not exist.

### Check the rules actually deny things

**Firestore → Rules → Playground**:

| Simulate | Expect |
|---|---|
| `get` on `users/SOME_OTHER_UID/transactions/x` as you | **Denied** |
| `create` on your own `transactions/x` with `amount_minor: -500` | **Denied** |
| `update` on `ocrJobs/{id}/results/{id}` | **Denied** |
| `get` on your own `users/{yourUid}/transactions/x` | **Allowed** |

If a denial passes, re-deploy the rules before putting real data in.

### Sign out

Sign out and reopen. You should be on the sign-in screen with no cached data
visible. Firestore's local cache is persistent, so sign-out clears it — and the
locally stored receipts go too, so a shared phone does not leak them.

---

# Day-to-day

```powershell
firebase emulators:start                      # Firestore + Auth, local, free
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
flutter test                                  # 225 tests
flutter analyze
flutter run
```

The emulator UI is at <http://localhost:4000>. To point the app at it, add this in
`main()` after `FirebaseService.initialise()`:

```dart
FirebaseService.firestore.useFirestoreEmulator('localhost', 8080);
await FirebaseService.auth.useAuthEmulator('localhost', 9099);
```

On an Android emulator use `10.0.2.2` rather than `localhost`.

---

# Troubleshooting

**`PERMISSION_DENIED` on something that should work**
Usually an unverified email — most rules require it. Confirm the address, then sign
out and in to mint a fresh token.

**`FAILED_PRECONDITION: The query requires an index`**
`firebase deploy --only firestore:indexes`. If it is a query I did not anticipate,
the error carries a creation link; use it, then add the index to
`firestore.indexes.json` so it survives the next deploy.

**No categories after signing up**
Sign out and in. Seeding runs on every sign-in and is idempotent.

**OCR finds no text**
Photograph the whole receipt, flat and well lit. ML Kit reads printed Latin text; a
crumpled or angled receipt gives it very little to work with.

**"This PDF is a scan"**
On-device OCR reads images, not scanned PDFs. Text-layer PDFs — anything exported
from online banking — work. For a scanned PDF, photograph the pages instead.

**Gradle: `File google-services.json is missing`**
Step 3. The file is gitignored, so a fresh clone always needs it placed by hand.

**Balance looks wrong**
It should never lag, since it is written with the transaction. If it does disagree,
delete and re-add the transaction — the correction is applied as a difference, so it
will settle.

---

# Never commit

- `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`
- Any service-account JSON (`firebase-adminsdk-*.json`) — that one **is** a real
  credential and bypasses every security rule

The repository stores no password, no banking credential, no full card number and no
CVV. Nothing in it should change that.
