# Deployment

What to deploy, in what order, and what to check.

There is not much to it: no functions, no storage, no build step on the server side.
The backend deployment is two files.

---

## The deploy

```bash
firebase deploy --only firestore:indexes      # 1
firebase deploy --only firestore:rules        # 2
# then build and ship the app                 # 3
```

Or both at once, which is what `firebase deploy` does:

```bash
firebase deploy --only firestore
```

**Indexes before rules, and both before the app.** An index takes time to build on a
database that already holds data; a query that needs one fails until it is ready.
Shipping an app whose query depends on an index still building produces
`FAILED_PRECONDITION` on a screen the user has already opened.

**Rules before the app, never after.** The rules are the access-control layer, so a
client that expects a permission the rules do not yet grant fails in production.

---

## Before deploying

```bash
flutter analyze                               # clean
flutter test                                  # 225 pass
flutter build apk --debug                     # a real compile
```

Then the checks a test cannot make:

- [ ] `firebase use` reports the intended project. Deploying rules to the wrong
      project is quiet and bad.
- [ ] Every new query shape has an index in `firestore.indexes.json`.
- [ ] Every new document field a client writes is permitted by a rule — and every
      field it must *not* write is refused.
- [ ] No service-account JSON anywhere: `git ls-files | Select-String "adminsdk"`
      finds nothing.
- [ ] `android/app/google-services.json` exists locally and is **not** tracked.

---

## Rules are a release

A rules deploy takes effect in seconds and applies to every connected client
immediately, including ones running an older build of the app. That cuts both ways:

- A rule that is **too permissive** is live the moment it deploys.
- A rule that is **too strict** breaks clients already in users' hands, with no way
  to roll them back.

So a rules change that removes a permission needs the app updated first; one that
adds a permission can go whenever. Test both directions in the **Firestore → Rules →
Playground** before deploying, and keep the list in `docs/security.md` current — it
is the checklist of what must stay refused.

---

## Android release

```bash
flutter build appbundle --release
```

Needs:

- `android/app/google-services.json` — gitignored, so CI needs it injected
- A signing key and `android/key.properties` — never committed
- **SHA-1 and SHA-256 fingerprints** added to the Firebase Android app. Without
  them some Firebase features reject requests from the signed build while working
  perfectly in debug, which is a confusing way to find out.

```bash
keytool -list -v -keystore <your-keystore> -alias <your-alias>
```

Add both under **Project settings → Your apps → Android → Add fingerprint**, then
download a fresh `google-services.json`.

### ML Kit and app size

The on-device text recogniser adds roughly 10 MB to the APK. The unbundled model is
downloaded through Google Play Services on first use, which is why the first import
on a new device takes a moment longer.

A device without Play Services — some Chinese Android builds, and most emulators
without Google APIs — cannot run the recogniser. The app reports that clearly rather
than failing obscurely, but it is worth knowing before promising the feature.

### Before uploading to Play

- [ ] `minSdk` 23 or higher — Firebase Auth 5.x and ML Kit both require it
- [ ] A real sign-up, a real receipt import, a real confirm, on a real device
- [ ] A **data deletion URL** in the Play listing. Play requires it, and the app has
      the feature: Settings → Delete account.
- [ ] The Data Safety form declares what is collected: email, name and financial
      records. **Documents are not collected** — they stay on the device, and the
      form should say so, because that is unusual enough to be worth stating.

---

## iOS

Not configured in this repository. It needs:

- `flutterfire configure` run for the iOS app, which rewrites `firebase_options.dart`
- `ios/Runner/GoogleService-Info.plist` placed and added to the Xcode target —
  gitignored, like the Android file
- A camera and photo-library usage description, or `image_picker` crashes on first
  use rather than asking
- ML Kit's pods, which `flutter build ios` adds automatically but which push the
  build time up noticeably the first time

---

## Web

The app compiles for web, but two things make it unsuitable for real use as-is:

- **`flutter_secure_storage` on web is not secure storage.** It falls back to
  browser storage, so a session token is readable by any script on the origin.
- **ML Kit has no web implementation.** Document import cannot work in a browser;
  everything else does.

---

## Watching the free tier

The limits that matter:

| | Free tier, per day |
|---|---|
| Firestore reads | 50,000 |
| Firestore writes | 20,000 |
| Stored data | 1 GiB |

Normal personal use is nowhere near these — the monthly rollups exist precisely so
that opening the analytics screen costs twelve reads rather than several thousand.

The number worth watching is **reads**, in the **Firestore → Usage** tab. A sudden
jump means a query lost its rollup path and started scanning transactions, which is
why `PeriodAggregate.source` reports which path an aggregate took.

---

## Rolling back

| Thing | How |
|---|---|
| Rules | **Firestore → Rules → version history**, restore a previous version |
| Indexes | Deleting one is safe; a query that needed it starts failing |
| App | Ship the previous build |
| Data | Only from a backup — see below |

### Backups

Not configured, and worth thinking about before this holds data anyone depends on.
Scheduled Firestore backups are a paid feature, so on the free tier the realistic
options are:

- **`exportMyData`**, which the app already has under Settings. It is a per-user JSON
  export, intended for the user's own benefit rather than as an operational backup —
  it reads at most 5,000 documents per collection and holds no history.
- A manual `gcloud firestore export` to a Cloud Storage bucket, which needs billing
  enabled even though the export itself is cheap.

Worth being clear-eyed about: on the free tier there is no point-in-time recovery,
and a bad write is permanent. That is one more reason the rules refuse structurally
wrong data — a negative amount, a missing owner — rather than trusting the client to
send only good writes.
