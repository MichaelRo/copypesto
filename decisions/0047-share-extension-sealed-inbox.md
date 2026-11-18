# 0047. The share extension seals to an inbox and never holds the history key; Shortcuts never hand out a secret

Status: Accepted (owner request, 2026-11-15)

Extends ADR 0002 (sealed at rest), ADR 0003 (secrets are masked and shown on request), ADR 0011 (no second process on the store) and ADR 0046 (Pesto on iPhone and iPad). Nothing they decide is reversed.

## Context
ADR 0046 names the share sheet and Shortcuts as ways a person hands something to Pesto on iOS. A share extension is a separate process with a memory limit near 120 MB. Giving it the history key would put the key that opens every clip into a process any app can start with arbitrary content; opening the SwiftData store from it would be a second process on the store, which ADR 0011 rules out. App Intents declared in the app target run in the app's own process.

## Decision
**A sealed inbox in the app group** (`group.net.copypesto.pesto`, `AppIdentity.appGroupID`; the only entitlement of the iOS app and of `PestoShare`).
- **Keys.** The app holds an X25519 inbox key pair. The private key is a Keychain item of the app (`AppIdentity.inboxKeyAccount`, when-unlocked, this device only, never synchronized; `InboxKeyStore`). Each time the app comes to the front it reads it (or makes it once) and publishes only the public key as `inbox-key.pestokey` in the group (`SharedInbox.publish`, a no-op when unchanged, a replacement when the file is missing, damaged or different). iOS Keychain reads do not prompt, so this read is not the Mac's "no Keychain read at launch" concern.
- **The extension** reads what was shared (`SharedContentChoice`: a picture over a link over text), seals it with HPKE (X25519, HKDF-SHA256, ChaChaPoly; the suite sync grants use) to the published key and writes one file per item into `inbox/` (`<uuid>.pestoinbox`, atomic, `completeFileProtection`). It links `PestoCore` but never opens the store and never reads the history key or the inbox private key. With no published key it says "Open Pesto once first" and saves nothing.
- **File format** (`InboxEnvelope`): `PESTOINB`, a version byte, the key's 16-byte id and HPKE's 32-byte encapsulated key, then the ciphertext; the whole header is the associated data. Inside: version, creation time, the type identifier and the payload. Only UTF-8 text (a link is its text) and the picture formats ingest stores are accepted, checked when sealing and again when opening.
- **Bounds** (`InboxPolicy`): text up to `ClipSizePolicy.maxTextBytes`; a picture up to 20 MB as it is, otherwise scaled from its file by ImageIO to 2,560 pixels on its longer side as a PNG, or refused with a clear message; at most 50 pending files and 200 MB. A file over the largest possible size is never read whole.
- **The drain** (`InboxDrain`, when the app becomes active): each file is opened with the private key and ingested through `StorageService.ingest`, so the size limit, the secret scan, masking, sealing and sync apply as to any copy; then the file is removed. A file that does not open (another key, damaged, truncated, oversized) or is refused is removed and counted, and the person is told how many were not added; nothing is ingested partially. Only a file the store failed to save is kept for the next activation, at most 7 days. Running it twice adds nothing twice.
- **What sits on disk, and for how long:** the public key, and sealed files from the moment of sharing until the app next comes to the front. Someone with the group container gets ciphertext they cannot open without the app's Keychain item; plaintext of a shared item never touches disk outside the sealed store. Someone who can write the group (only code signed by the same team, on iOS) could replace the public key until the app's next activation republishes its own; they still could not read what was sealed to the real one.

**Shortcuts** (`AddToPestoIntent`, `SearchPestoIntent`, `ClipEntity`, `PestoMobileShortcuts`) run in the app's process. Add ingests directly. Search and the clip entity query hand out only what `ShortcutClipSearch.isOffered` allows: never a clip with a secret (not its text, not its mask, not by its id), never one still being judged or covered by the content filter; each entity is an id, one line of preview text and the kind. The Mac's Copy from Pesto keeps its rule, now spelled once as `ShortcutClipSearch.matches`.

## Consequences
- On a device the app group, and an App ID for `net.copypesto.pesto.share`, must be registered on the developer portal and in both provisioning profiles; a simulator honors the entitlement with ad-hoc signing.
- A share made before the app's first launch is refused, not queued.
- The extension cannot read the person's theme, so it draws in system colors with the brand green from `BrandPalette`.
- Losing the inbox private key (a restored device without the Keychain item) makes pending files unreadable: they are removed and counted.

## Docs affected
`AGENTS.md` (security invariant 2, the Mobile paragraph), `docs/testing.md` ("The iPhone and iPad app"). The README and the guide say nothing about the iPhone app until it is released (ADR 0046).
