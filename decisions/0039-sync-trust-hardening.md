# 0039. Pairing is eight stretched words, a Mac keeps the group and epoch it joined, a log's signer must be its Mac, and requests expire

Status: Accepted

Nothing about the network, the backup file format or the encryption of clips changes. The sync folder format does not change: a Mac that has these rules reads and writes the same files. It amends the pairing code and the group choice of ADR 0018, and it is the follow-up to the security review behind ADR 0038.

## Context
The review treated the folder as untrusted storage that anyone who can write to it may fill with files. It found that the six-word code could be ground to a match, that a Mac followed whatever group and epoch the folder showed, and that one enrolled Mac could sign into another's log.

## Decision
- **Pairing words are eight words, stretched** (`SyncPairingCode`: 80 bits, derived with PBKDF2-HMAC-SHA256 at 600,000 iterations). Six unstretched words (60 bits) let a folder writer who generates key pairs on both sides until the two screens match find one after about 2^30 tries a side, which is minutes of work, and then receive the real sync key from the approving Mac. At eighty bits and about 0.2 s a try the same search needs about 2^40 slow derivations. Both Macs must run this version to show the same words; one that does not shows different words, so the person refuses: it fails safe. The sheets show the words in two rows of four. The words are derived once per request and kept, because a refresh asks again and again.
- **A Mac keeps the group and the epoch it joined** (`SyncHighWater.vaultFloor`, sealed with the high-water marks): a folder that shows an older epoch of that group (a newer vault file hidden or deleted) is refused with a message, and a folder that shows a different group in place of it is refused too. A different vault planted beside the real one is ignored, because the group this Mac joined wins over a smaller vault id (`SyncGroupManager.open(preferring:)`). Reset Sync raises the floor on the Macs that open the new epoch; Leave Sync and changing the folder clear it. Before this, hiding `vault-2` rolled every Mac back to epoch 1, whose key a removed Mac may still hold, and each Mac re-wrote its whole history under it.
- **A log's signer must be the Mac it names** (`SyncTrust.deviceKeyIDs`): a manifest for device A signed by the key of enrolled Mac B is refused. A device the trust does not name (the vault's creator after it left) is checked against the signers as before.
- **A join request is shown for 24 hours** (`SyncController.joinRequestLifetime`), by its signed `createdAt`. Planted requests cannot keep a prompt in front of the person forever.
- **A file a provider has listed but not downloaded is not read yet, for any provider** (`SyncFileAvailability`, the `SF_DATALESS` flag): Dropbox and Google Drive folders hold such placeholders, and reading one blocks until the system fetches it. Pesto asks for it in the background and waits for the next pass, as it does for iCloud Drive.

## Reviewed, not changed
- **A planted file name in a log folder** (a garbage `.pestolog` with a far-ahead range) stops reading that log, or breaks this Mac's own chain until the next snapshot. Anyone who can write to the folder can already delete segments, which does the same, so this adds no power; the status it shows is accurate enough.
- **`.partial` files are created by name** after removing a file of that name. A symlink swapped in that gap would make Pesto write through it. Dropbox and iCloud Drive do not sync symlinks, so a folder writer cannot plant one through the provider; a person with the folder on their own disk can already do more.
- **A file planted at this Mac's backup name** stops automatic backups until it is removed. The message says so; a folder writer can already do this by deleting the backup.
- **Backup chunks share one key with random 96-bit nonces.** At a billion chunks across every backup of a Mac the chance of one repeated nonce is about 2^-37, so a per-file key would change the backup format for no practical gain.
- **`SyncHead.open` is not called**, so ADR 0018's sentence that a head below the stored mark is refused is not implemented. The high-water chain check (`SyncHighWater.decide`) is what refuses a rolled-back, forked or re-ordered log.

## Consequences
- Pairing takes about a fifth of a second longer on each Mac, once per request.
- A person who deliberately restores the sync folder to an earlier state sees the refusal and uses Leave Sync, then joins again.
- Tests: `SyncFormatTests` (eight words, the fixed vector, the iteration count, the signer binding), `SyncFolderServiceTests` (a hidden newest vault, a planted vault, a replaced vault, an emptied folder), `SyncControllerTests` (a stale request), `SyncFileAvailabilityTests`.
- The sync pictures and the guide change words ("eight", not "six"): `make pictures` retakes the pairing sheets.

## Docs affected
- `docs/guide/settings.md`, `docs/guide/faq.md`, `docs/guide/privacy-and-security.md`, `docs/feature-reference.md`, `docs/sync-design.md`, `docs/testing.md`, `docs/release.md`, `docs/release-sync-profile-steps.md`, `AGENTS.md` (the pairing words)
- `Sources/Core/Sync/CLAUDE.md`, `decisions/README.md`
- the website's guide pages, synced from `docs/guide/` after merge
