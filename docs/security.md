# Security

What is protected, how, and what is not. Written to be checkable rather than
reassuring.

---

## The model in one paragraph

There is no server. The app talks to Firestore directly, and the security rules are
the entire access-control layer — whatever they allow is what is possible. That makes
this document short and the rules file important. The honest summary: **isolation
between users is complete and enforced; integrity of a user's own derived figures is
enforced by the app, not by the rules.**

---

## Identity

- Email and password only. No social providers, no passwordless links.
- **A verified email address is required before any financial data is reachable.**
  It is the only account-recovery path, so an unverified account must not accumulate
  records it could then lose access to. The rules check
  `request.auth.token.email_verified`, which comes from the token — not a field in a
  document, which the user could write themselves.
- The user id always comes from the verified session. No repository accepts a user
  id argument. A client can put anything in a request body; it cannot forge an ID
  token.
- **Email enumeration protection is on**, and the app matches it: `ErrorMapper`
  returns one joint message — "That email or password is incorrect" — for
  `invalid-credential`, `wrong-password`, `user-not-found` and `invalid-email` alike,
  and the forgot-password screen reports success whatever the server says. Separate
  messages would turn either endpoint into an oracle for which addresses are
  registered.
- Changing a password requires the current one, checked by reauthentication. That
  satisfies Firebase's recent-login requirement and stops someone with a borrowed
  unlocked phone from taking the account over.
- Session tokens live in the platform keychain through `flutter_secure_storage`.

---

## Isolation — fully enforced

Every document lives under `users/{uid}/…`, and the rule is one condition applied by
prefix.

This is **structural** rather than conditional, and the difference matters. Under a
flat layout with a `user_id` field, a client can construct a query for another user's
documents and the rules deny it. Here the path itself is rejected: there is no query
to construct. The integration test asserts that reaching for
`users/someone-elses-uid/transactions` raises `permission-denied` rather than
returning an empty list — a silent empty result would be indistinguishable from "that
user has no transactions", which is a much weaker guarantee.

Collection groups are the one place that reasoning does not hold, because a group
spans every user's subcollections. The client uses exactly one — counting split lines
that reference a category — and its rule requires the owner filter rather than
assuming it:

```
match /{path=**}/splits/{splitId} {
  allow read: if signedIn() && resource.data.user_id == request.auth.uid;
}
```

A query without `where('user_id', '==', uid)` fails rather than returning a filtered
subset, which is the behaviour wanted: a silent partial result would hide the mistake.

---

## Integrity — enforced by the app, not the rules

This is the trade the free plan makes, and it should be understood rather than
glossed over.

On the paid plan, derived figures — account balances, budget spend, savings totals,
an OCR candidate's confirmed status — were written only by Cloud Functions, and the
rules refused every client. Without functions the client must write them, and **no
rule can check one document's increment against another document's amount**: rules
see a single write in isolation.

So a modified client could post a transaction of 100 and increment its own balance by
1,000.

**Why that is acceptable here.** The only person who can do it is the account's
owner, to their own records. This is a personal ledger: a user who falsifies their
own balance has achieved nothing except lying to themselves. No user can affect
another user's data, which is the property anyone else depends on.

**What the app does regardless.** Every derived figure is written in the *same
Firestore transaction* as the record that causes it, with `FieldValue.increment`:

- Either the transaction and the balance both land, or neither does. A dropped
  connection cannot leave them disagreeing.
- Two devices posting at once both count, because the server applies the delta to
  whatever the current value is. A read-modify-write would make the later write
  discard the earlier transaction.

In exchange, balances are **immediate** rather than a second behind — which a trigger
could not offer.

---

## What the rules still refuse

Isolation is not the only thing they carry. These are enforced regardless of what the
client sends:

| Rule | What it prevents |
|---|---|
| `amount_minor` must be a positive **int** | A float in a money field, reintroducing the rounding `Money` exists to prevent; and a negative amount contradicting its type |
| `user_id` must equal the writer | A document that lies about its owner, which would corrupt the collection-group queries |
| `type` must be in the enum | An invented transaction type that no screen knows how to render |
| `ocrJobs/*/results/*` is **immutable** | A correction on the review screen rewriting the evidence it was made against |
| A candidate must be created `PENDING` | An import creating something already marked confirmed, bypassing review entirely |
| `created_transaction_id` cannot be cleared once set | The same receipt being imported twice |
| `seeded_at` cannot be cleared | Re-running the seeder and duplicating all 22 categories |
| `is_system` categories cannot be deleted | Orphaning a transaction that points at one |
| Notifications: update is `is_read`/`read_at` only | Rewriting an alert's text after the fact |
| Contributions are immutable | A savings ledger entry being edited rather than reversed |
| No `list` on `users` | Enumerating the user collection |

---

## The product rule

"OCR output never becomes a transaction without review" rests on four barriers, three
of which survive having no server:

1. **The parser** returns null for a field it could not read. A candidate with no
   amount keeps a null amount rather than a zero that looks like a reading, and a
   document with no amount *and* no date produces no candidate at all.
2. **The pipeline** writes candidates and stops. `startJob` contains no code path
   that creates a transaction.
3. **The rules** require a candidate to be created `PENDING`, and refuse to let
   `created_transaction_id` be cleared once set.
4. **`confirmCandidate`** requires an amount, an account and a date, and writes the
   transaction and the candidate update in **one Firestore transaction**.

Postgres carried the fourth as a table constraint; the paid plan carried it in a
Cloud Function. Here it is an atomic client transaction — which still means a
confirmed candidate always points at a transaction that exists, and a transaction
from an import always has a candidate behind it.

What is *lost* relative to the paid plan: a rule that stopped a client writing
`status: CONFIRMED` directly. A modified client could mark a candidate confirmed
without a transaction. Again: only its own.

Confirming the same candidate twice returns the existing transaction id rather than
creating a second one, so a double tap or a retried call is harmless.

---

## Documents

**They never leave the device.** Not uploaded, not held by a third party, not
reachable by any URL. This is a stronger position than either arrangement this
project has had before — a signed URL is readable by anyone holding it for ten
minutes, and a Firebase download token forever.

Stored under `finora_documents/<uid>/<documentId>/`, scoped by user id so two
accounts on one phone cannot read each other's files. Sign-out deletes the signing-out
user's folder, alongside Firestore's persistent cache, so a shared device does not
leak the previous user's statements.

Uploads are validated by **magic number**, not extension: `receipt.pdf.exe` and a PNG
renamed `.pdf` are both refused.

---

## Secrets

There are none.

| | Where it lives | In the app? |
|---|---|---|
| OCR API key | **Does not exist** — ML Kit runs on-device | n/a |
| Firebase API key | `google-services.json`, `firebase_options.dart` | Yes, by design |
| Service-account JSON | Nowhere in this repository | No |

The specification required that OCR credentials never ship in the client. Without a
server to hold one, the honest way to satisfy that is not to have a key at all.

**The Firebase API key is not a secret in Firebase's model.** It identifies the
project; what anyone can do is decided by the rules and the caller's token. It is not
harmless either — it can be used to call the project's own auth endpoints, enough to
create junk accounts and burn quota — so the platform config files are gitignored and
the key should be API-restricted in the Cloud Console.

A **service-account JSON** (`firebase-adminsdk-*.json`) *is* a real credential: it
grants full project access and bypasses every rule here. None is in this repository
and none should be.

---

## Never stored

- Passwords — Firebase Auth holds the hash; the app never sees or stores one
- Banking credentials of any kind
- Full card or account numbers — `account_number_last4` is four digits, named so the
  limit is visible at the point of use
- CVV
- Private API keys

---

## Never shown

`ErrorMapper` is the only code that knows what a `FirebaseException` looks like. Each
`AppException` carries a `message` written for the user and a `debugDetail` that is
logged and never rendered.

So the UI cannot display a stack trace, a Firestore error code, or an internal file
path. Logging is `INFO` in debug and `WARNING` in release, and nothing is sent
off-device — log records can contain document paths, and shipping those somewhere is
not a thing a finance app should do quietly.

---

## Client-side validation, and where it is also enforced

| Check | In the app | Also in the rules |
|---|---|---|
| Amount greater than zero | form validator | ✅ |
| Positive integer minor units | `Money` | ✅ |
| Owner stamped on every document | repositories | ✅ |
| Splits sum to the total | review banner + `replaceSplits` | ❌ — not expressible |
| Transfer accounts differ | transfer sheet | ❌ |
| Transfer currencies match | `createTransfer` | ❌ |
| Upload size and type | `FileValidator` | n/a — local only |
| Withdrawal within goal balance | `contributeToGoal` | ❌ |
| Candidate has amount, account, date | Confirm disabled + `confirmCandidate` | ❌ |

The ❌ rows are the ones a server would have carried. Each is enforced inside a single
Firestore transaction, so it cannot be violated by a *failure*; it could be violated
by a deliberately modified client, acting on its own data.

---

## What remains possible

Stated rather than left to be discovered.

- **A user can falsify their own derived figures** with a modified client, as above.
- **A user can write nonsense into their own records** — an expense that never
  happened, a merchant that does not exist. This is a personal ledger; the data is
  theirs to be wrong about.
- **Quota abuse against the auth endpoints.** The API key is in the app, so sign-up
  and sign-in can be called directly. Firebase rate-limits these; restricting the key
  by API narrows it further. App Check would close it properly and is not wired up.
- **A compromised device is a compromised account.** Biometric lock is a UI gate, not
  encryption; the ID token in the keychain is what grants access. Sign-out clears both
  the Firestore cache and the stored documents, which is why that step exists.
- **Read volume is not capped per user.** A client could page its own history
  repeatedly and exhaust the free tier's 50,000 daily reads, which would make the app
  stop working until midnight UTC. Not a security problem; worth knowing.
- **No App Check.** Requests are authenticated but not attested, so a request from a
  script with a valid token is indistinguishable from one from the app. The rules do
  not depend on the client being genuine for *isolation* — which is why this is a
  quota and integrity concern rather than a confidentiality one.
