# 0002. Clip data is sealed at rest and bound to its item, Clear Everything replaces the key, and the plaintext exceptions are listed

Status: Accepted

## Context
A clipboard history holds whatever a person copied, including things they would never write to disk on purpose. The
threats are another account on the same Mac, someone reading the disk or the database file, and a process that can
write the store but cannot use the Keychain. A process running as the same user on an unlocked Mac can ask the Keychain
for the key as Pesto does; that is not answered here. The key is not Secure Enclave wrapped, and no document says it is.

SwiftData cannot run `VACUUM` or set `secure_delete`, and a second SQLite connection would collide with Core Data's, so
deleting a row leaves its bytes in freed pages and the write-ahead log until they are reused
(`ClearEverythingResidueTests` measures this).

## Decision
**The key.** `BlobEncryption` uses AES-GCM-256 under a random per-install key, a generic-password item in the login
Keychain (service `AppIdentity.keychainService`, account `AppIdentity.blobKeyAccount`,
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`): not synchronizable and never leaves the Mac. If the key is missing or
does not open the history, Pesto does not make a new one silently: it asks (`KeyLossChoice`) whether to quit, start
empty, or start empty and open restore. A new Mac cannot open an old store; the encrypted backup is for that (ADR 0010).

**What is sealed.** Each item is its own ciphertext, with the item's id and the field name as associated data
(`BlobEncryption.associatedData`, `pesto.v2|<item id>|<field>`), so a ciphertext moved to another row or field does not
open:
- the clip's content, `ClipboardBlob.encryptedData` (`blob`);
- its preview, `previewCiphertext` (`preview`): every preview except a real color's and a secret's masked one. Text
  found in a picture is sealed too, after being scanned for secrets (`SensitiveContentDetector.detectAnywhere`);
- custom title, note, tags, and a linked page's title and site name, as one JSON `ItemMetadata` in
  `metadataCiphertext` (`metadata`); the old columns survive only as `legacy*` attributes read while no ciphertext
  exists;
- the on-device search-by-meaning vector, `embeddingCiphertext` (`embedding`);
- link preview images, one sealed file per item (`LinkPreviewImageStore`);
- the duplicate fingerprint is an HMAC under a key derived from the install key (`ContentHash`), not a bare hash.

Opened previews, metadata and vectors are cached in memory in `PreviewTextCache` and dropped when the history locks or
is cleared.

**Older rows convert at launch, once.** `StorageService.bindCiphertextToItems`, `sealItemMetadata` and `sealEmbeddings`
run off the main actor in batches, each versioned by a `Setting` (`ciphertextBindingVersion`, `metadataSealingVersion`,
`embeddingSealingVersion`; legacy plaintext previews by `encryptLegacyPreviews`, `previewEncryptionVersion`). They
decrypt the old form, seal the new one, open the result and only then replace the row; a failed row is left untouched
and retried, an interrupted run continues at the next launch. `ClipboardBlob.aadBound` and
`ClipboardItem.previewAADBound` mark a bound row; a row without the flag opens with no associated data.

**A number is not a color.** A color's preview is the one preview kept in plaintext, so what counts as a color is
strict (`ContentClassifier`): a bare hex string needs a letter A-F and a digit; `#` with three differing digits
(`#178`, `#404`) is a reference number; `rgb()`, `rgba()`, `hsl()` and `hsla()` count only when
`ColorLiteralParser.isFunctionalColor` reads the whole text. Whatever filed a clip as a color, `ColorPreviewPolicy`
judges the preview again before it is stored in the clear (`ColorClearTextGateTests`); storage code never compares with
`.color` itself. `StorageService.repairMisreadClips` (`Setting.clipRepairVersion`) turns earlier misread "colors" into
text with a sealed preview.

**Spotlight.** Pesto indexes nothing. The first launch removes any index an older version left (`SpotlightCleanup`).

**Clear Everything replaces the key.** `StorageService.clearEverything` deletes rows, files and caches, then replaces
the install key in place (`BlobEncryption.rotateKey`: `SecItemUpdate`, so the item keeps its access list; `SecItemAdd`
if the item is gone), so what is left in freed pages is ciphertext nobody can open. If the key cannot be replaced, the
clips stay deleted, the old key stays and the failure is logged. Rows go first, so a crash in between leaves the old
state. A test or UI-test launch keeps its fixed session key, so rotation is a no-op there (seam:
`StorageEnvironment.keyRotator`). Backups are sealed under their own backup key and are unaffected.

## Consequences
**Left in the clear, on purpose** (the privacy guide lists the same): the app a clip came from, when it was copied,
its size and pixel dimensions, kind, whether it is pinned, how often it was pasted, its collection, expiry and shortcut
slot, character length and code language, whether it is marked sensitive, flagged adult or came from another device;
the category and masked preview of a secret; colors; a coarse perceptual fingerprint of each picture; collection names,
icons and rules. And one file: `last-item.json` in the support folder, owner-only, holding the preview, kind, time and
source app of the latest clip that contains no secret, for the `pesto` command and AppleScript (ADR 0011). The History
Lock clears it, and a delete or a clear removes it.
- Nothing can filter by title, note, tag or vector inside a database query; search and smart collections filter in
  memory.
- Anyone who can read the user's login Keychain can read the key.
- After Clear Everything and a relaunch the app is a fresh install as far as the key goes; restore re-ingests under the
  new key. Plaintext fields stay in freed pages until reused, and old Time Machine or APFS snapshots of the Keychain
  hold the old key.
- When sync returns, the record mapping must carry the binding flags with the ciphertext.
- Tests: `OnDiskEncryptionTests` scans a real store for plaintext of content, a URL, image bytes, a title, a note, a
  tag, a page title and a vector, for small clips and for ones written to an external file; `CiphertextBindingTests`,
  `ItemMetadataEncryptionTests`, `EmbeddingEncryptionTests`, `StorageRepairTests`, `SpotlightCleanupTests`,
  `HistoryLockGateTests` and `ClearEverythingResidueTests` cover the rest.

## Docs affected
`docs/guide/privacy-and-security.md`, `Sources/Core/Storage/CLAUDE.md`, `AGENTS.md` (Security invariants 2).
