# Document storage

Where uploaded receipts and statements live, and why they live there.

---

## On the device, not in the cloud

Firebase requires the paid Blaze plan for Cloud Storage on any project created after
October 2024. This app runs on the free tier, so there is no bucket — documents are
stored in the app's own directory on the phone, and only their *metadata* goes to
Firestore.

That is a constraint, but it is not only a constraint. Compare the three
arrangements this project has had:

| Approach | Who can read a document |
|---|---|
| Supabase, signed URLs | Anyone with the link, for 10 minutes |
| Firebase download URL | Anyone with the link, **forever** |
| **On the device** | Only this app, on this phone |

For bank statements, the third is plainly the best of the three. A document that was
never uploaded cannot be exposed by a leaked link, a misconfigured rule, or a
provider's breach.

### What it costs

Two things, both stated in the app rather than left to be discovered:

- **Documents do not sync between devices.** Signing in on a second phone shows
  every transaction, with the receipt itself missing. The *record* is in Firestore;
  only the image is local. The review screen and the document viewer say so when a
  file is absent rather than showing a broken image.
- **Uninstalling the app deletes them.** The transactions survive, because they are
  in Firestore. The scans do not.

Anything a user genuinely needs to keep should be kept elsewhere too, and the app
does not pretend otherwise.

---

## Paths

```
<app documents>/finora_documents/<uid>/<documentId>/<fileName>
```

Stored against the document record as a **relative** path — `uid/documentId/file.jpg`.

That detail is load-bearing. An absolute path would break on iOS, where the
application container is given a new directory on every app update: every receipt
would silently detach from its transaction, and the failure would appear weeks later
as a screen full of missing images.

Three further properties follow from the shape:

**Scoped by user id.** Two accounts on one phone cannot read each other's files, and
sign-out can clear one user's documents without touching the other's.

**The document id is in the path.** Firestore generates ids locally with no round
trip, so the id exists before the file is written. The path is therefore
deterministic: a failed save can be retried to the same place, and deleting a
document can remove its whole folder without listing anything.

**The file name is sanitised, not trusted.** `sanitiseFileName` collapses path
separators, removes `..`, replaces anything outside `[A-Za-z0-9._-]` with an
underscore and truncates at 120 characters. `../../../etc/passwd` becomes
`_etc_passwd`; an empty result becomes `file`.

---

## Validation

`FileValidator` runs before anything is written, and checks the **magic number**
rather than the extension:

| Type | Leading bytes |
|---|---|
| JPEG | `FF D8 FF` |
| PNG | `89 50 4E 47` |
| WebP | `52 49 46 46` … `57 45 42 50` |
| PDF | `25 50 44 46` (`%PDF`) |

So `receipt.pdf.exe` and a PNG renamed `.pdf` are both refused, and the recorded
`mime_type` is what the bytes actually are rather than what the name claimed. The
pipeline routes on that type, which is why it matters: a PDF path applied to a JPEG
fails confusingly deep inside the extractor.

Size is capped by `AppConfig.maxUploadMb` (15 MB by default). With no storage rules
to enforce it server-side, this is a client-side limit — which is acceptable here
because the only thing it protects is the user's own disk.

---

## Reading files back

```dart
final bytes = await documentStore.read(document.storagePath);
```

Previews render with `Image.memory`. Large images are decoded at display size —
`cacheHeight` on a preview tile, full resolution only in the zoomable viewer. A
12-megapixel phone photo costs about 48 MB of image cache at full size, and a list of
them would exhaust memory on a mid-range device.

A missing file returns null from `previewBytes` rather than throwing, so a record
synced from another device degrades to a placeholder instead of an error.

---

## Deletion

Three paths, each ordered so the worse failure cannot happen.

**A document deleted by the user.** The OCR trail goes first — jobs, their raw
results, and any *unconfirmed* candidates — then the attachment is cleared from any
transaction that referenced it, then the Firestore record, then the file. A failure
at the last step orphans a file, which is recoverable; a failure earlier would leave
a record pointing at nothing, which is not.

Transactions themselves are never deleted. A receipt is evidence for a transaction,
not the transaction itself, and deleting a photo must never delete a record of
spending. Confirmed candidates are kept too — by then they are the audit trail of a
transaction that exists.

**Sign-out.** Every document belonging to the signing-out user is deleted, alongside
Firestore's persistent cache. A shared phone must not leave the previous user's bank
statements readable by the next.

**Account closure.** `deleteAccountCompletely` walks every Firestore collection,
removes the user's whole document folder, and deletes the Firebase user **last** — so
a failure partway leaves an account that can still sign in and retry, rather than a
locked-out user whose records are half gone.

---

## Preprocessing

`ImagePreprocessor` prepares a **copy** for recognition and for storage. The original
bytes are stored untouched, so the receipt a user reopens in a year is exactly what
they photographed.

- **Avatars** are compressed to 400 KB before being written.
- **OCR copies** may be rotated and contrast-adjusted. ML Kit reads from a file, so
  the bytes are written to the *temporary* directory, read, and deleted in a `finally`
  block — deliberately not the documents directory, because a working copy of a bank
  statement should not survive the operation that created it.
