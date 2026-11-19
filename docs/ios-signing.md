# Signing the iPhone and iPad app

The iOS app (`PestoMobile`) and its four extensions build and test on a simulator with no signing at all. A real
iPhone or iPad needs an Apple Developer account, a few identifiers on the developer portal, and provisioning
profiles. This page lists them once. ADR 0046 explains why the iOS app shares the Mac app's bundle identifier.

## What the portal needs

Identifiers → App IDs (explicit, type App), each with the capabilities listed:

| Bundle identifier | Target | Capabilities |
|---|---|---|
| `net.copypesto.pesto` | `PestoMobile` (the app) | App Groups |
| `net.copypesto.pesto.share` | `PestoShare` | App Groups |
| `net.copypesto.pesto.autofill` | `PestoAutoFill` | App Groups, AutoFill Credential Provider |
| `net.copypesto.pesto.widget` | `PestoWidget` | App Groups |
| `net.copypesto.pesto.keyboard` | `PestoKeyboard` | App Groups |

Identifiers → App Groups: register `group.net.copypesto.pesto`, then tick it under App Groups on each of the five App
IDs.

The shared Keychain groups (`net.copypesto.pesto.quick-insert` for AutoFill and the keyboard, ADR 0051 and 0061;
`net.copypesto.pesto.widget` for the widget, ADR 0052) are entitlements prefixed with the team's identifier; the
keyboard carries the quick-insert group alone. As far as is known they need no switch on the portal; if a profile is
refused for them, add Keychain Sharing to that App ID. Each extension needs its own profile (Xcode makes them with
automatic signing; an App Store build needs one per App ID).

## Building to a device

1. On the device, once: connect it, unlock it, tap Trust; then Settings → Privacy & Security → Developer Mode → on,
   and restart when asked.
2. `make build-mobile-device DEVICE="<the device's name>"` builds the app and its extensions for that device with
   automatic signing. The team comes from `APPLE_TEAM_ID`, which the `Makefile` reads from the Developer ID
   certificate in the keychain; pass `APPLE_TEAM_ID=…` to choose another. Xcode creates the profiles on the first run
   (`-allowProvisioningUpdates`).
3. To run it, open `Pesto.xcodeproj`, choose the `PestoMobile` scheme and the device, and press ⌘R. On first launch
   the device may ask you to trust the developer under Settings → General → VPN & Device Management.

The project is generated (`make generate`), so a team picked by hand in Xcode's Signing & Capabilities tab is lost on
the next generate; the `make` target passes it every time instead.

When Xcode reports a problem:
- "No profiles for …" or "App Group not found": that App ID lacks a capability from the table. Add it on the portal
  and build again.
- "Device not registered": let Xcode register it (Signing & Capabilities → Register Device), or add it under Devices
  on the portal.

## What only a device can check

A simulator has no iCloud Keychain, no real iCloud Drive, no Face ID hardware and no real screen capture. These are hand
checks on a device:
- the sync key arriving through iCloud Keychain from a Mac, and the folder picker against iCloud Drive (ADR 0046);
- Face ID for Show and the History Lock (ADR 0054), and the App Switcher cover;
- a screen recording, mirroring or AirPlay covering the cards;
- AutoFill: Settings → General → AutoFill & Passwords → turn Pesto on, then insert a clip from a text field's AutoFill
  menu; no secret is ever offered (ADR 0051);
- the keyboard: Settings → General → Keyboard → Keyboards → Add New Keyboard → Pesto, with and without Full Access,
  in another app's text field (ADR 0061; the list is in `docs/testing.md`, "The keyboard on a device");
- the widget on the Home Screen, its Copy action, and the Locked state (ADR 0052, 0055);
- the share sheet from Safari, Notes and Photos (ADR 0047);
- "Add Clipboard to Pesto" from the Action Button or Back Tap, and iOS's paste prompt;
- the checks that need Apple Intelligence or a real GIF in another app (AI actions, Ask, Describe Image, sharing a GIF in and out) are listed in `docs/testing.md`, "iPhone and iPad: what only a device can check".

## Uploading to App Store Connect

Once, on the portal and in App Store Connect:
1. An **Apple Distribution** certificate (Xcode → Settings → Accounts → the team → Manage Certificates → + → Apple
   Distribution). It is separate from the Developer ID certificate; keep its .p12 and password in the password
   manager.
2. An App Store profile for each of the five App IDs above (Profiles → + → App Store Connect). They are not secret and
   can be downloaded again; Xcode → Settings → Accounts → Download Manual Profiles installs them.
3. The app record: App Store Connect → Apps → + → New App → iOS, name Pesto, bundle ID `net.copypesto.pesto`, any SKU
   (an internal reference no one sees, such as `pesto-ios`), and Full Access for the team's users.

Each release:
1. `make archive-mobile` archives `PestoMobile` and its extensions (Release, any iOS device) into
   `.build/xcode-ios-app/Pesto-iOS.xcarchive`, signed for the team the `Makefile` finds (`APPLE_TEAM_ID`).
2. `open .build/xcode-ios-app/Pesto-iOS.xcarchive` opens it in Xcode's Organizer: Distribute App → App Store Connect →
   Upload, with automatic signing (or Manual, choosing the five App Store profiles).
3. In App Store Connect the build appears after processing; fill in the listing and review notes from
   `docs/app-store-ios.md` and submit.

## Distribution

Device builds from Xcode need no App Store Connect record. Giving the app to anyone else means the App Store (TestFlight
is its optional beta stage); there is no iOS equivalent of the Mac's Developer ID download. That record and its review
notes (AutoFill is text insertion only, not a password manager; why the keyboard asks for Full Access) wait until a
release is planned.
