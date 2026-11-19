# The iPhone and iPad app on the App Store

What App Store Connect asks for, answered for Pesto, and what still needs the maintainer. The Mac app is not on the
App Store and does not change (Developer ID, notarized). Signing and the developer portal are in
[ios-signing.md](ios-signing.md). The website keeps its rule of never claiming an iPhone app until one is released.

## Before the first upload

- [ ] An App Store Connect record for `net.copypesto.pesto`, platform iOS (the maintainer; the bundle ID is the Mac
      app's on purpose, ADR 0046, so the sync key can arrive through iCloud Keychain).
- [ ] A distribution certificate and an App Store profile for the app and its three extensions
      (`.share`, `.autofill`, `.widget`), each with the app group `group.net.copypesto.pesto` and the Keychain groups
      in [ios-signing.md](ios-signing.md).
- [ ] A privacy policy URL. App Store Connect requires one even for an app that collects nothing. The guide's
      [Privacy and security](guide/privacy-and-security.md) describes only the Mac, so it is not enough by itself:
      publish it together with the iPhone and iPad section drafted under "Privacy policy for iPhone and iPad" below
      (the guide gets that section at release, ADR 0046). Blocks the upload.
- [ ] The export compliance answer, confirmed by the maintainer (below). Blocks the upload.
- [ ] The screenshots below.
- [x] A privacy manifest in every bundle and a Face ID purpose string (`MobileSubmissionTests`).

## Listing

| Field | Value |
|---|---|
| Name | Pesto |
| Subtitle (30) | Keep what you copy |
| Category | Productivity (secondary: Utilities) |
| Price | Free. Every feature, no in-app purchase (ADR 0001) |
| Age rating | 4+ (no web browser, no user-to-user content, nothing from a server) |
| Support URL | The GitHub repository's issues page, or the website's support page |

**Promotional text (170):** Your copies, kept and searchable on iPhone and iPad. Sealed on your device, and in step
with Pesto on your Mac through a folder you choose. No account, no server.

**Description:**

> Pesto keeps what you copy. Add it with Paste, from the share sheet in any app, or with the Add Clipboard to Pesto
> shortcut, and find it again as a card you can search, pin, edit and file into collections.
>
> Your history is encrypted on your device. Things that look like passwords, keys or card numbers are masked until you
> ask to see them, and copies an app marks as private are never kept.
>
> With Pesto on your Mac, turn on sync and choose the same folder, such as iCloud Drive. Clips are sealed so that only
> your own devices can open them; there is no Pesto server and no account.
>
> • One page of clip cards, with search that finds words inside pictures
> • Pinned clips, collections and smart collections
> • Snippets with fill-ins
> • Edit a clip's text
> • Insert clips in any app through AutoFill (text only, never passwords)
> • A Home Screen widget with your recent clips
> • Lock your history with Face ID
> • On iPad: a sidebar, keyboard shortcuts, drag and drop, and every multitasking size
>
> Pesto has no analytics and no tracking. Link previews ask the linked site for its title and picture, and you can turn
> them off.

Check each line against the build being submitted: a feature that is not in it comes out of the description.

**Keywords (100):** clipboard,clipboard manager,copy paste,history,snippets,notes,paste,clips,text,sync

## App Privacy (the "nutrition label")

- **Data collection: "No, we do not collect data from this app."** Pesto sends nothing to the developer or to anyone
  else: no analytics, no crash reporting SDK, no account (invariant 5, `NetworkGuardTests`). Sync files go to a folder
  the person picks, readable only with their own keys; that is the person's storage, not collection.
- **Tracking:** none (`NSPrivacyTracking` false in every manifest).
- Link previews make a request to the site a clip links to, from the device; Apple's definition of collection is data
  the developer or its partners receive, which this is not. Say so in the review notes if asked.

## Privacy policy for iPhone and iPad (draft)

To publish with the Mac's privacy page at release. Check each line against the build being submitted.

> **What Pesto keeps.** Clips you add on your iPhone or iPad, and clips your other devices send through sync, are
> stored on the device, encrypted with a key that never leaves it. Nothing is sent to us; we have no server.
>
> **Sync.** Optional. Your devices exchange sealed files through a folder you choose, such as iCloud Drive. Only your
> devices hold the keys that open them.
>
> **Link previews.** When on (the welcome offers them, and Settings can turn them off), Pesto asks a link's own site
> for its title and picture. That site sees your IP address, as it would if you opened the link.
>
> **Apple Intelligence.** AI actions, Describe Image and Ask Pesto run on the device's own model. No clip is sent
> anywhere.
>
> **Face ID.** The History Lock asks iOS to check your face or passcode. Pesto never sees your face data.
>
> **Extensions.** The share extension, AutoFill and the widget never open your history. The app gives each a small
> sealed file: AutoFill gets pinned clips, snippets and recent text, the widget gets recent clips, and neither ever
> gets a secret. With the History Lock on they stay empty unless you choose otherwise.
>
> **Sharing out.** When you share a picture or a GIF, iOS needs a file: Pesto writes one for the share and deletes it
> when the share ends, when the history locks or is cleared, and at the next launch.
>
> **No analytics, no tracking, no ads.**

## Export compliance

`ITSAppUsesNonExemptEncryption` is `NO` in the app's Info.plist. Pesto encrypts only the person's own data (AES-GCM and
HPKE from CryptoKit) to protect it at rest and between their own devices, which is the usual case for the exemption.
**The maintainer confirms this answer**: it is a legal statement, and the reasoning here is not legal advice.

## Notes for the reviewer

> Pesto needs no account and no Mac to review.
>
> - To add clips: copy text in any app, open Pesto and press the Paste button; or share text, a link or a picture to
>   Pesto from the share sheet; or write a note with the compose button.
> - AutoFill: Pesto's AutoFill extension provides text insertion only (the "ProvidesTextToInsert" capability). It does
>   not store, offer or fill passwords, passkeys or one-time codes. To try it: Settings → General → AutoFill &
>   Passwords → turn on Pesto, then in any text field long-press → AutoFill → Pesto, and pick a clip.
> - Sync is optional and needs Pesto for Mac and a folder both devices can open (such as iCloud Drive). It goes through
>   files in that folder; there is no server. It can be skipped on the welcome screen.
> - The History Lock (Settings, or the welcome's second step) asks for Face ID before clips show.
> - The widget: add "Recent Clips" from the Home Screen's widget gallery. Tap a clip to copy it.

## Screenshots

App Store Connect needs the largest iPhone and the largest iPad sizes it lists at upload time (check its screenshot
specification then: the sizes change with new devices). Take them from the iPhone Pro Max and the 13-inch iPad Pro
simulators with the seeded UI-test launch (`PESTO_UITEST_SEED=basic`), light appearance:

1. The library with cards (iPhone), the same with the sidebar (iPad, landscape)
2. A search that finds text inside a picture
3. A clip's detail with Edit Text
4. Collections (iPad sidebar)
5. The AutoFill picker
6. The widget on the Home Screen (needs a device or a hand-made frame; the simulator's Home Screen works)
7. The welcome's sync step

They are not part of `make pictures` yet; adding an iOS pass there is the next step for this list.

## Hand checks before submitting

The device-only checks in [ios-signing.md](ios-signing.md) ("What only a device can check"), on the build that will be
uploaded (a Release build with the App Store profile), plus the Face ID prompt and its text on a Face ID iPhone. Without
TestFlight, put that build on a device through Xcode (Window → Devices and Simulators) before uploading it.
