# 0058. The Mac widget: Recent Clips from a sealed snapshot, only in a build signed with both provisioning profiles

Status: Accepted (owner decision, 2026-11-19: profile-signed release only, no plaintext exception, optional)

Extends ADR 0002 (sealed at rest), ADR 0018 (the sync key and its provisioning profile), ADR 0052 (the iOS widget,
whose snapshot, sealing and links this reuses) and ADR 0055 (the widget says Locked). Nothing they decide is reversed.

## Context
A desktop or Notification Center widget on macOS is a WidgetKit extension, which runs in the App Sandbox (Pesto's
Controls extension already does; that WidgetKit refuses one without it is reported by developers, not measured here).
Pesto is a non-sandboxed Developer ID app. The iOS widget opens a snapshot the app seals into the app group, with a key
from a Keychain group only the app and the widget hold (ADR 0052). On the Mac, both halves depend on signing:

- **A shared file.** The extension's sandbox lets it reach only its own container and the containers of the app
  groups it claims. Since macOS 15 the system protects group containers: a process that opens one without a claim
  authorized by an embedded provisioning profile (or a team-prefixed group, or a Mac App Store build) gets the "would
  like to access data from other apps" prompt, and a widget extension, which cannot show it, has been reported to exit
(forum thread 758478). iOS-style `group.`
  identifiers have been fully supported on macOS since February 2025 when a profile authorizes them; a Mac profile for
  an App ID with the App Groups capability authorizes the team's groups. On macOS the App Groups entitlement is
  "validation-required": a claim no profile authorizes does not stop the launch but clears the process's
  entitlements-validated flag, and the data protection keychain then ignores every Keychain entitlement it has.
  (Apple: "Configuring app groups", the App Groups entitlement; DTS, "App Groups: macOS vs iOS: Working Towards
  Harmony", forum thread 721701.)
- **A shared key.** A Keychain item two processes can both read needs the data protection keychain and a shared
  access group (`keychain-access-groups`). On macOS "these entitlements must be authorized by a provisioning profile"
  (TN3137). The file-based login keychain, where the history key lives, has per-item ACLs instead of groups and is not
  reachable from a sandboxed extension by design.
- Measured on this Mac, 2026-11-19: the installed Developer ID profile "Pesto Sync" (App ID `net.copypesto.pesto`)
  authorizes `com.apple.application-identifier`, `com.apple.developer.team-identifier` and `keychain-access-groups`
  `NBD55BZ3N4.*`, and no app group. The Controls extension (`net.copypesto.pesto.controls`) has no profile today.

A development build is signed "Pesto Development" or with the Developer ID certificate and no profile. It can claim
neither the group nor the Keychain group: claiming them anyway either costs it the sync key's iCloud Keychain item
(validation cleared) or makes macOS refuse to launch it (an unauthorized restricted entitlement).

## Decision
- **Only a release signed with both profiles offers the widget.** `make release SYNC_PROFILE="…" WIDGET_PROFILE="…"`
  signs the app with `PestoSyncWidget.entitlements` (the application identifier and team as for sync, the app group
  `group.net.copypesto.pesto`, and `keychain-access-groups` `<team>.net.copypesto.pesto` first, so every item the app
  writes stays where it is, then `<team>.net.copypesto.pesto.widget`) under the app's profile, and the extension with
  `PestoControlsWidget.entitlements` (the sandbox, its application identifier and team, the same app group, and the
  widget's Keychain group alone) under the extension's own profile, and compiles the widget into the extension
  (`PESTO_MAC_WIDGET`). `WIDGET_PROFILE` without `SYNC_PROFILE` stops the build. Any other build (`make run`, `make
  install`, the gate, a release with `SYNC_PROFILE` alone or none) is exactly what it was: the app's entitlements empty
  or the sync pair, the extension sandboxed with nothing else, and **no Recent Clips widget in the gallery**.
- **The widget lives in the existing `PestoControls` extension**, not a new target. WidgetKit lets one extension carry
  both a control and widgets; one extension means one more App ID and profile instead of two, and a build without the
  widget embeds nothing new and empty (a widget bundle cannot leave a widget out at run time: `WidgetBundleBuilder`
  has no `if`, only `if #available`). Its deployment target drops from macOS 26 to macOS 15, the app's: the control
  stays behind `#available(macOS 26.0, *)`, and the widget needs macOS 15 (`WidgetCenter.currentConfigurations`). The
  control still never reads a clip; the extension's process now may, through the widget, and only in that build.
- **The app writes the snapshot only when it can prove it may.** `WidgetSharing.current` reads the running app's own
  signed entitlements (`SecTaskCopyValueForEntitlement`) and answers yes only for the app group and a Keychain group
  that ends in `.net.copypesto.pesto.widget`; without both, `AppPaths.sharedGroupDirectory` stays nil on the Mac, the
  app never calls `containerURL(forSecurityApplicationGroupIdentifier:)` (no prompt), never asks WidgetKit, and never
  touches that Keychain group. With them, it keeps the snapshot of ADR 0052 (the same format, file name, bounds,
  eligibility through `ShortcutClipSearch.isOfferedOutsidePesto`, `WidgetSnapshotSelection`, key account and purpose)
  only while a Pesto widget is installed (`WidgetCenter.currentConfigurations`, asked at launch, when the shelf opens,
  on wake, on any `pesto://` link and every ten minutes); with none, the file and the key go.
- **What it holds follows the Mac's lock and cover** (`WidgetSnapshotGate`): with the History Lock switched on, a
  Locked snapshot with no clip (ADR 0055's default; the Mac has no "Show clips in widgets and AutoFill" setting, so
  there is no way to keep clips there while the lock is on); with clip contents covered (Hide Clip Contents, or a
  detected screen share with that setting on), a Hidden snapshot with no clip ("Clip contents hidden", a new optional
  field `isHidden` and state `.hidden`; iOS never writes it); otherwise the clips. A change of lock, cover, theme or
  history rewrites it (the history a second after the save, the others at once); Clear History, Clear on Lock, Clear on
  Quit and Clear Everything rewrite it from what the store still holds before they return (`WidgetSnapshotKeeper`).
- **Choosing a clip goes through the app.** The Mac widget does not write to the clipboard itself: every pasteboard
  write of a clip goes through `AppState.writeItem` (the lock check, a secret kept to this Mac and concealed, the
  own-write gate). Each tile is a `Link` (the small widget's `widgetURL`) to the same `pesto://clip/<UUID>`, `…/show`
  and `…/open` links as iOS (`WidgetLink`, decided by `WidgetTap` with in-place copy off). The Mac app now handles
  them (`AutomationRequest.widget`): only for a clip still offered outside Pesto, and while locked only the lock
  screen. Copy writes it through `writeItem` and moves it to the front as a shelf copy does (`noteCopied`); Show opens
  the shelf searching for it; Open hands a link clip to the browser only when its whole text is one web address
  (`WidgetTap.webURL`). An unknown or ineligible id only opens the shelf. A link from a web page can do no more than
  the widget could. The widget's configuration (When a Clip Is Chosen, Show) is the iOS one.
- **Shared code.** The widget's views, provider, configuration and reader move to `Sources/Widget`, compiled into both
  widget extensions and `PestoMobileTests`; only the in-place copy (`CopyClipIntent`) and the iOS bundle stay in
  `Sources/MobileWidget`. The theme's colors are resolved once in Core (`WidgetSnapshot.Theme.resolve`) for both apps.

### What the maintainer does in the developer portal
In `docs/release.md`, "The Mac widget": enable App Groups on the App ID `net.copypesto.pesto` with
`group.net.copypesto.pesto`, regenerate its Developer ID profile, register `net.copypesto.pesto.controls` with App
Groups and the same group, create its Developer ID profile, then `make export SYNC_PROFILE=… WIDGET_PROFILE=…` and
`scripts/check-widget-signing.sh` on the exported app.

### Rejected
- **A plaintext snapshot** in a folder the extension could read without a profile: rejected by the owner; it would be
  a new exception to ADR 0002 that no lock or cover could take back.
- **A team-prefixed group without a profile.** A team-prefixed group passes macOS 15's container check without a
  profile, but the Keychain group still needs one (TN3137), and a self-signed development build has no team at all. A
  snapshot sealed with a key kept in the file beside it would be plaintext in all but name.
- **The app group as the Keychain access group** (documented for iOS; DTS has not confirmed it on macOS): the explicit
  `keychain-access-groups` entry is the documented Mac path and keeps the key out of any other member of the group.
- **An in-place copy in the extension's process.** It would put a pasteboard write outside `AppState`'s write path,
  so a clip could reach Universal Clipboard unprotected; and whether a sandboxed widget's App Intent may write the
  general pasteboard was not measured.
- **A second, new extension target.** Its own App ID and profile, and an empty extension in every build without it.

## Consequences
- What sits outside the store while a Mac widget is installed: what ADR 0052 lists, at most 512 KB, sealed, in
  `~/Library/Group Containers/group.net.copypesto.pesto`, and a key in the data protection keychain under the widget's
  group. Code signed by the same team and authorized for that group could read both; nothing else can.
- A clip deleted or made secret leaves the snapshot about a second after the save while Pesto runs. A widget removed
  leaves the file and key until Pesto next asks (at most ten minutes while it runs). Quitting Pesto leaves the last
  snapshot, as leaving the iOS app does.
- Choosing a clip brings Pesto forward for a moment, as any link does; whether macOS gives focus back to the app the
  person was in is a hand check.
- Only a build with both profiles can show any of this: the profile check (`scripts/check-widget-signing.sh`), the
  widget in the gallery, the snapshot opening in the extension and the Keychain item both read are hand checks
  (`docs/testing.md`). Everything else is tested with a temporary folder and an in-memory Keychain.
- If the regenerated app profile did not authorize the app group, the app would lose the iCloud Keychain sync key
  (validation cleared): `check-widget-signing.sh` refuses such a build before it ships.

## Docs affected
`AGENTS.md` (security invariant 2, Module boundaries' Mobile paragraph), `docs/release.md` ("The Mac widget"),
`docs/testing.md` (hand checks), `docs/guide/privacy-and-security.md`, `README.md`, `decisions/README.md`.
