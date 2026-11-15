# 0051. AutoFill inserts a clip from a small sealed set the app keeps ready; text insertion only, never passwords

Status: Accepted (owner request, 2026-11-15)

Extends ADR 0002 (sealed at rest), ADR 0003 (secrets are masked and shown on request), ADR 0046 (Pesto on iPhone and iPad, no keyboard extension) and ADR 0047 (the share extension's sealed inbox). Nothing they decide is reversed.

## Context
ADR 0046 ruled out a keyboard extension and named AutoFill's text insertion as the way to put a clip into another app. Since iOS 18 a credential provider extension can declare `ProvidesTextToInsert` under `ASCredentialProviderExtensionCapabilities`; the system then lists it in a text field's AutoFill menu, calls `prepareInterfaceForUserChoosingTextToInsert()`, and the extension answers with `completeRequest(withTextToInsert:)`. The extension is a separate process under a tight memory limit, started by the system whenever the person asks, with Pesto not on screen. Giving it the history key, or the store, would put every clip's key into a second process (ADR 0011, ADR 0047).

## Decision
**Text insertion only.** `PestoAutoFill` (`net.copypesto.pesto.autofill`) declares `ProvidesTextToInsert` and nothing else: no passwords, passkeys or one-time codes, no credential identities, no `ASCredentialIdentityStore`. Every other entry point cancels the request (`ASExtensionError.credentialIdentityNotFound` for an identity, `.failed` otherwise). Pesto deliberately drops a password manager's copies (ADR 0004) and must not offer to fill a login.

**One setting, off by default:** Insert from Pesto in other apps (`Setting.quickInsertEnabled`). With it off there is no file and no key; turning it off removes both.

**The quick-insert set** (`QuickInsertSet`, chosen by `QuickInsertSelection`): pinned clips (at most 50), then snippets (at most 50), then the newest other clips (at most 30), each newest first; a clip over 32 KB is left out and the whole set stays under 256 KB, filled in that order (`QuickInsertPolicy`). Only text a field can take: text, code, a link as its address, a color as its value. Never a picture or a file, and never what `ShortcutClipSearch.isOfferedOutsidePesto` refuses: a clip with a secret (not its text and not its mask), one still being judged, one the content filter flagged (whatever the filter's setting), or one that expires. A snippet is offered only when every placeholder is one Pesto fills alone (a date, a time, a new ID, the caret); it is expanded when inserted and its caret marker removed. A snippet that asks for values, reads the clipboard or names the target app is left out, since the extension cannot prompt or know them.

**Sealing.** The extension must open the set, so unlike the inbox it needs a key both processes hold: a random AES-256 key in the Keychain group `$(AppIdentifierPrefix)net.copypesto.pesto.quick-insert` (`keychain-access-groups` of the app and the extension, not of the share extension), this device only, never synchronized, readable after first unlock (`SharedKeychainSecretStore`, account `AppIdentity.quickInsertKeyAccount`). The app lists its own `$(AppIdentifierPrefix)net.copypesto.pesto` first, so every other item it writes (history key, inbox key, sync keys) stays in its own group, as before. The file is `quick-insert.pestoquick` in the app group: `PESTOQIS`, a version byte, then AES-GCM over the JSON set, with the header and the purpose `pesto.quick-insert.v1` as associated data (`QuickInsertEnvelope`); written whole, atomically, with complete file protection, and read with a 2 MB bound. **This key opens only that file**: never the store, the inbox or sync, and nothing else is sealed with it.

**When it is written.** The app rewrites the set a second after a save changes the history (any change: a copy, an edit that makes a clip secret, a pin, a sync), and when it leaves the foreground. Clear History writes an empty set at once (pinned clips return with the next write). The feature turned off, or the history unavailable, removes the file and the key. The app never reads the set back; the extension never writes it.

**The picker** (`QuickInsertMenu`): a search field over sections Pinned, Snippets and Recent, a line or two per clip, tap to insert, Cancel to cancel. With no set it says so and how to turn the setting on; with an empty one it says there is nothing to insert. No editing, no fill-in prompts.

## Consequences
- What sits outside the store: up to 256 KB of the person's own non-secret text, sealed, in the app group; and a key in a Keychain group the app and the AutoFill extension share. Code signed by the same team could read both, as with the inbox (ADR 0047); nothing else can.
- A clip deleted or made secret leaves the set within a second of the save while Pesto runs; if Pesto is killed in that second, the next launch or foreground rewrites it.
- On a device: an App ID for `net.copypesto.pesto.autofill` with the AutoFill Credential Provider capability, the app group and the keychain group, in both provisioning profiles. The person enables Pesto under Settings > General > AutoFill & Passwords.
- The simulator signs without a team, so there `$(AppIdentifierPrefix)` is empty and the group is `net.copypesto.pesto.quick-insert`; `PestoAppIdentifierPrefix` in each Info.plist carries the same build setting, so the code always names the group its entitlement holds.

## Docs affected
`AGENTS.md` (security invariant 2's documented exceptions, the Mobile paragraph), `docs/testing.md` ("The iPhone and iPad app"). The README and the guide, the privacy page included, say nothing about the iPhone app until it is released (ADR 0046, ADR 0047); this set joins the privacy page's exceptions in the release that ships the app.
