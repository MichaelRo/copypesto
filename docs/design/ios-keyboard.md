# Optional iOS Keyboard Extension (`PestoKeyboard`) — Research & Design Spec

Status: Shipped (`PestoKeyboard` is implemented per accepted ADRs 0061–0063; extensions beyond those are proposed in ADR 0064).
Builds on ADR 0051 (sealed quick-insert set for AutoFill) and ADR 0055 (History Lock and `showsClipsOutsideWhileLocked`).
Amends ADR 0046 ("No keyboard extension"): the keyboard stays strictly **optional** while AutoFill (`PestoAutoFill`) remains the zero-Full-Access default.

---

## 1. Context and Motivation

ADR 0046 originally excluded a custom keyboard extension because iOS isolates third-party keyboards unless the user grants **Allow Full Access**, which triggers Apple's system alert stating that the keyboard could transmit everything the user types. ADR 0051 shipped `PestoAutoFill` (`net.copypesto.pesto.autofill`) using iOS 18+ `ProvidesTextToInsert` instead.

In practice, AutoFill's text-insertion sheet takes two to three taps through the system field menu and is unavailable in some custom text views (games, WebViews, or fields that suppress AutoFill). A dedicated optional keyboard (`PestoKeyboard`) offers one-tap insertion right beside the system keyboard for people who explicitly add it in **Settings > General > Keyboard > Keyboards**.

To keep Pesto's security invariants intact (ADR 0002, ADR 0003, ADR 0051):
- The keyboard extension **never** accesses the SwiftData history store, the per-install history key (`AppIdentity.blobKeyAccount`), the inbox key (`AppIdentity.inboxKeyAccount`), or sync keys.
- It **never** links networking or analytics code and holds no network entitlement.
- It reads **only** the sealed quick-insert set already maintained for AutoFill (`quick-insert.pestoquick`).

---

## 2. What Already Exists in the Codebase

Everything required to produce, seal, filter, and clear the insertable clip set is already built and tested in `PestoCore` and `PestoMobile`:

| Component | Location | Role |
|---|---|---|
| `QuickInsertSet` | `Sources/Core/Model/QuickInsertSet.swift` | Codable payload (`createdAt`, `[QuickInsertEntry]`), plus `.empty`. |
| `QuickInsertEntry` | `Sources/Core/Model/QuickInsertEntry.swift` | Entry `id`, `section` (`.pinned`, `.snippets`, `.recent`), `kind`, `title`, `text`, `expandsOnInsert`. |
| `QuickInsertPolicy` | `Sources/Core/Model/QuickInsertPolicy.swift` | Bounds: max 50 pinned, 50 snippets, 60 recent; 32 KB per entry; 256 KB total plaintext; 2 MB file read cap; 120-char title cap; 1 s rewrite debounce. |
| `QuickInsertMenu` | `Sources/Core/Model/QuickInsertMenu.swift` | View-ready model (`State`: `.unavailable`, `.empty`, `.ready`) and `groups(matching:)` grouped by section. |
| `QuickInsertSelection` | `Sources/Core/Paste/QuickInsertSelection.swift` | Picks eligible `.text`, `.code`, `.url`, `.color`, and bounded `.image` thumbnail clips allowed by `ShortcutClipSearch.isOfferedOutsidePesto` (excludes secrets, pending analysis, flagged clips, and expiring clips). Snippets remain eligible for AutoFill when `TemplateExpander.fillsWithoutSystemContext` holds (`KeyboardMenu` excludes interactive `expandsOnInsert` snippets via `fillsWithoutAsking`). |
| `QuickInsertEntry.insertionText(at:)` | `Sources/Core/Paste/QuickInsertEntry+Insertion.swift` | Expands dates/times/UUIDs and strips `{{cursor}}` (`clipboardProvider: { "" }`). |
| `QuickInsertEnvelope` | `Sources/Core/Crypto/QuickInsert/QuickInsertEnvelope.swift` | Seals/opens `QuickInsertSet` with `SealedFileEnvelope` (`PESTOQIS`, version `1`, AAD purpose `"pesto.quick-insert.v1"`). |
| `QuickInsertFile` | `Sources/Core/Crypto/QuickInsert/QuickInsertFile.swift` | Reads/writes `quick-insert.pestoquick` (`AppIdentity.quickInsertFileName`) in `AppPaths.sharedGroupDirectory` (`group.net.copypesto.pesto`). |
| `QuickInsertKeyStore` | `Sources/Core/Crypto/QuickInsert/QuickInsertKeyStore.swift` | Stores/loads the AES-256 key (`AppIdentity.quickInsertKeyAccount`) via `SharedKeychainSecretStore` in `$(AppIdentifierPrefix)net.copypesto.pesto.quick-insert`. |
| `QuickInsertTarget` & `MobileAppState+QuickInsert.swift` | `Sources/Mobile/` | Rewrites `quick-insert.pestoquick` 1 s after store saves and on leaving foreground; empties on Clear History or when `historyLock.holdsOutsideSurfaces`; removes file + key when disabled. |
| `Setting.quickInsertEnabled` | `Sources/Core/Runtime/Setting.swift` | Boolean (`false` by default) controlling whether the app writes `quick-insert.pestoquick`. |
| `Setting.showsClipsOutsideWhileLocked` | `Sources/Core/Runtime/Setting.swift` | Boolean (`false` by default; ADR 0055). When History Lock is on and this is off, `MobileAppState+QuickInsert` writes `QuickInsertSet.empty`. |
| `AutoFillViewController` & `InsertPickerView` | `Sources/MobileAutoFill/` | Reference consumer: opens `QuickInsertFile.current` with `QuickInsertKeyStore`, builds `QuickInsertMenu`, handles `.unavailable` / `.empty` / `.ready`, shares `Sources/MobileShare/BrandAccent.swift`. |

Note: `TemplateExpander.fillsWithoutAsking` currently excludes `{{clipboard}}`, `{{app}}`, interactive fill-in fields, and returns `true` for `{{date}}`, `{{time}}`, `{{datetime}}`, `{{isodate}}`, `{{weekday}}`, `{{date+Nd}}` / `{{date-Nd}}`, `{{uuid}}`, and `{{cursor}}` (plus `{{selection}}` which expands to `""` via default `selectionProvider`). `QuickInsertSelection` uses `TemplateExpander.fillsWithoutSystemContext` so interactive fill-in snippets (and bounded `fieldMemory`) are preserved for AutoFill while `KeyboardMenu` filters them out.

---

## 3. `UIInputViewController` Sandbox & Full Access Boundaries

A custom keyboard runs as an `app-extension` under extension point `com.apple.keyboard-service` (`UIInputViewController`), strictly constrained by iOS Jetsam (~48–60 MB RAM ceiling) and sandbox rules.

### 3.1 Without Full Access (`hasFullAccess == false`)

This is the default state after a user adds the keyboard in iOS Settings before toggling **Allow Full Access** (or if the user leaves Full Access off).

**Blocked by iOS:**
- **App Group container (`group.net.copypesto.pesto`):** `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)` is inaccessible (`nil` or sandbox permission denied), so `QuickInsertFile.current` cannot be read.
- **Shared Keychain access groups:** Keychain queries targeting `$(AppIdentifierPrefix)net.copypesto.pesto.quick-insert` fail (`errSecItemNotFound` / entitlement blocked), so `QuickInsertKeyStore.key()` cannot read the key.
- **`UIPasteboard.general`:** Pasteboard reads return empty / are blocked in restricted mode.
- **Network & haptics:** No network access (also unwanted by Pesto's invariants); audio clicks/haptics are restricted.

**What works (`hasFullAccess == false`):**
- `textDocumentProxy.insertText(_:)` and `textDocumentProxy.deleteBackward()` work normally in the host text field.
- `advanceToNextInputMode()` / `handleInputModeList(from:with:)` work when `needsInputModeSwitchKey` is `true` so the user can always switch back to the system keyboard.
- **Self-contained starter snippets compiled into the extension:** Dynamic templates that require zero history data work offline inside the restricted sandbox using Core's `TemplateExpander`:
  - `{{date}}` (today's date in user locale)
  - `{{time}}` (current time in user locale)
  - `{{isodate}}` (`yyyy-MM-dd`)
  - `{{weekday}}` (full weekday name)
  - `{{uuid}}` (fresh lowercase UUID)
- **Calm Full Access prompt:** Instead of an error screen or broken empty list, show the 5 built-in dynamic starter chips at the top/grid, accompanied by a calm, transparent explanation card:
  - Title/lead: explaining that **Allow Full Access** in **Settings > General > Keyboard > Keyboards > Pesto** lets the keyboard read your Pinned, Snippets, and Recent clips from Pesto.
  - Privacy reassurance (factual, no absolutes): clips stay sealed on this device, Pesto has no network access and records no keystrokes; AutoFill remains available without Full Access.

### 3.2 With Full Access (`hasFullAccess == true`)

When the user enables **Allow Full Access** in iOS Settings (requiring `RequestsOpenAccess = YES` in `Info.plist`):

**Granted:**
- **App Group container (`group.net.copypesto.pesto`):** `QuickInsertFile.current` can open and read `quick-insert.pestoquick` (atomic, 2 MB read bound).
- **Shared Keychain access group (`$(AppIdentifierPrefix)net.copypesto.pesto.quick-insert`):** `QuickInsertKeyStore(secrets: SharedKeychainSecretStore(accessGroup: AppIdentity.quickInsertKeychainGroup(in: .main))).key()` retrieves the quick-insert key after first device unlock.
- **Zero secrets, zero store access:** The keyboard extension's entitlements include **only** `group.net.copypesto.pesto` and `$(AppIdentifierPrefix)net.copypesto.pesto.quick-insert`. It does **not** carry `$(AppIdentifierPrefix)net.copypesto.pesto` (the app's private Keychain group holding `blobKey`, `inboxKey`, and sync keys) and never touches the SwiftData store.

**Pasteboard behavior (`UIPasteboard.general`) even with Full Access:**
- On iOS 16+, reading `UIPasteboard.general` programmatically triggers the system **"PestoKeyboard would like to paste from..."** permission dialog unless the user manually sets **Settings > Apps > Pesto > Paste from Other Apps** to **Allow** or interacts with a `UIPasteControl`.
- **Design rule:** `PestoKeyboard` **must not** call `UIPasteboard.general` on its own. It reads only `QuickInsertFile.current` (`quick-insert.pestoquick`) plus its built-in dynamic starters, and never triggers unexpected paste permission prompts while switching keyboards. (If live-clipboard insertion were ever desired later, it would require a dedicated `UIPasteControl` button, not automatic reads.)

---

## 4. Target & Configuration Specification (`PestoKeyboard`)

### 4.1 Identity Constants (`Sources/Core/Runtime/AppIdentity.swift`)
Add to `AppIdentity`:
```swift
public static let keyboardBundleID = "\(bundleID).keyboard"
```
Reuse existing quick-insert constants without adding any new Keychain group or file format:
- `AppIdentity.appGroupID` (`"group.net.copypesto.pesto"`)
- `AppIdentity.quickInsertFileName` (`"quick-insert.pestoquick"`)
- `AppIdentity.quickInsertKeyAccount` (`"net.copypesto.pesto.quickInsertKey"`)
- `AppIdentity.quickInsertKeychainGroupName` (`"net.copypesto.pesto.quick-insert"`)
- `AppIdentity.appIdentifierPrefixInfoKey` (`"PestoAppIdentifierPrefix"`)

### 4.2 XcodeGen Target (`Pesto.yml`)
Add target `PestoKeyboard` and embed it in `PestoMobile`:
- **Name:** `PestoKeyboard`
- **Type:** `app-extension`
- **Platform:** `iOS` (`deploymentTarget: "26.0"`)
- **Sources:**
  - `Sources/MobileKeyboard` (excluding `Info.plist`, `*.entitlements`)
  - `Sources/MobileShare/BrandAccent.swift` (matches `PestoAutoFill`)
- **Dependencies:**
  - `package: PestoCore`, `product: PestoCore`
  - `sdk: UIKit.framework`, `sdk: SwiftUI.framework`
- **Settings:**
  - `PRODUCT_BUNDLE_IDENTIFIER: net.copypesto.pesto.keyboard`
  - `PRODUCT_NAME: PestoKeyboard`
  - `MARKETING_VERSION: "1.7.0"` / `CURRENT_PROJECT_VERSION: "9"` (matching `PestoMobile` and sibling extensions)
  - `TARGETED_DEVICE_FAMILY: "1,2"`
  - `ENABLE_HARDENED_RUNTIME: "NO"`
  - `INFOPLIST_FILE: Sources/MobileKeyboard/Info.plist`
  - `CODE_SIGN_ENTITLEMENTS: Sources/MobileKeyboard/PestoKeyboard.entitlements`
  - `APPLICATION_EXTENSION_API_ONLY: "YES"`
  - `ENABLE_USER_SCRIPT_SANDBOXING: "YES"`
- Embed `target: PestoKeyboard` (`embed: true`) inside `PestoMobile.dependencies`.

### 4.3 Entitlements (`Sources/MobileKeyboard/PestoKeyboard.entitlements`)
Exact keys (must match `EntitlementsTests` once updated):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.net.copypesto.pesto</string>
    </array>
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)net.copypesto.pesto.quick-insert</string>
    </array>
</dict>
</plist>
```
Verify: `PestoMobile.entitlements` keeps `$(AppIdentifierPrefix)net.copypesto.pesto` first, followed by `.quick-insert` and `.widget`, so Pesto's private Keychain items remain isolated from `PestoKeyboard`.

### 4.4 `Info.plist` (`Sources/MobileKeyboard/Info.plist`)
- `CFBundleDisplayName`: `Pesto`
- `PestoAppIdentifierPrefix`: `$(AppIdentifierPrefix)` (required by `AppIdentity.quickInsertKeychainGroup(in: .main)` and pinned by `EntitlementsTests`)
- `NSExtension`:
  - `NSExtensionPointIdentifier`: `com.apple.keyboard-service`
  - `NSExtensionPrincipalClass`: `$(PRODUCT_MODULE_NAME).KeyboardViewController`
  - `NSExtensionAttributes`:
    - `IsASCIICapable`: `<false/>` (non-QWERTY insertion keyboard; ensures iOS shows the Globe / input-mode switcher cleanly)
    - `PrefersRightToLeft`: `<false/>`
    - `PrimaryLanguage`: `en-US`
    - `RequestsOpenAccess`: `<true/>` (exposes the **Allow Full Access** toggle in Settings)

### 4.5 Privacy Manifest (`Sources/MobileKeyboard/PrivacyInfo.xcprivacy`)
Must match `MobileSubmissionTests` requirements:
- `NSPrivacyTracking`: `<false/>`
- `NSPrivacyTrackingDomains`: `[]`
- `NSPrivacyCollectedDataTypes`: `[]`
- `NSPrivacyAccessedAPITypes`:
  - `NSPrivacyAccessedAPICategoryUserDefaults`: `["CA92.1"]`
  - `NSPrivacyAccessedAPICategoryFileTimestamp`: `["C617.1"]`
And add `"Sources/MobileKeyboard"` to `MobileSubmissionTests.bundleFolders`.

---

## 5. Architecture & UI States (`Sources/MobileKeyboard/`)

### 5.1 View Controller Lifecycle (`KeyboardViewController: UIInputViewController`)
1. **Height constraint:** Set an explicit input view height constraint (e.g. `280` pt on iPhone, `300` pt on iPad / regular width, adjustable by trait collection) so SwiftUI `UIHostingController` never collapses to zero height inside the input view.
2. **Reload on appearance:** Reload `QuickInsertFile.current` in `viewWillAppear(_:)` and whenever `textDidChange(_:)` or `traitCollectionDidChange(_:)` indicates a foreground switch, because the user may switch to Pesto, copy/pin/clear a clip, and switch back without the extension process terminating.
   - **Optimization:** Cache the file modification date (or decode only when `url` attributes / modification date changed) so switching text fields doesn't redundantly re-decrypt the 256 KB file on every focus change.
3. **Zero state retention on disappearance:** Drop decoded `QuickInsertSet` from memory when `viewDidDisappear(_:)` runs if the extension stays warm in background, keeping RSS tiny and leaving no decrypted clips sitting idle.
4. **System keyboard switching & editing keys:**
   - Observe `self.needsInputModeSwitchKey`: when `true`, render a Globe button wired to `handleInputModeList(from:with:)` (for touch-down / long-press switcher menu) and `advanceToNextInputMode()` (tap), so the user is never stuck in Pesto's keyboard.
   - Provide compact **Backspace** (`textDocumentProxy.deleteBackward()`), **Space** (`insertText(" ")`), and **Return** (`insertText("\n")`) utility keys in the bottom chrome bar alongside the Globe button so quick edits don't require switching keyboards twice.
5. **No nested search field:** Because `PestoKeyboard` *is* the active input method, tapping a `TextField` inside a custom keyboard cannot summon the system QWERTY keyboard. Therefore, unlike `InsertPickerView` in AutoFill, the keyboard **does not** render a `.searchable` box; instead it provides one-tap **section filter pills** (`All`, `Pinned`, `Snippets`, `Recent`, `Today/Starters`) and fast scrolling.

### 5.2 Built-in Starter Chips (Always Available, Even Without Full Access)
Define a small Core or extension-local list `KeyboardStarter` (reusing `TemplateExpander.expansion(of:isSnippet:true, at: .now, clipboardProvider: { "" })`):
- **Date** (`{{date}}`)
- **Time** (`{{time}}`)
- **ISO Date** (`{{isodate}}`)
- **Weekday** (`{{weekday}}`)
- **UUID** (`{{uuid}}`)

Evaluate at tap time so timestamps and UUIDs are fresh on every press.

### 5.3 Four UI States (`KeyboardMenuState`)
Model the view state cleanly in a testable pure struct (similar to `QuickInsertMenu`):

1. **Restricted (`!hasFullAccess`):**
   - Header bar: `"Pesto"` + Globe button (when `needsInputModeSwitchKey`).
   - Built-in dynamic starter chips row (`Date`, `Time`, `ISO Date`, `Weekday`, `UUID`) — immediately usable even with Full Access off.
   - Calm information card explaining:
     - *"Allow Full Access to insert Pinned, Snippets, and Recent clips."*
     - *"Turn on Allow Full Access in Settings > General > Keyboard > Keyboards > Pesto. Pesto never connects to the internet or reads what you type in other keyboards."*
2. **Unavailable (`hasFullAccess == true && menu.state == .unavailable`):**
   - Occurs when `Setting.quickInsertEnabled` is `false`, `quick-insert.pestoquick` hasn't been written yet, or History Lock cleared it (`QuickInsertFile` missing or unreadable).
   - Shows the 5 dynamic starter chips row plus a calm message:
     *"Open Pesto and turn on Insert from Pesto in other apps in Settings."* (And if History Lock is on, *"If History Lock is on, unlock Pesto or allow clips while locked."*)
3. **Empty (`hasFullAccess == true && menu.state == .empty`):**
   - Occurs when History Lock is active with `showsClipsOutsideWhileLocked == false` (app wrote `QuickInsertSet.empty`), after Clear History before new copies, or when no eligible non-secret text clips exist.
   - Shows the 5 dynamic starter chips row plus:
     *"No clips available to insert. Locked histories and clips with secrets stay out unless allowed in Pesto's Settings."*
4. **Ready (`hasFullAccess == true && menu.state == .ready`):**
   - Top bar: Section filter chips (`All`, `Pinned`, `Snippets`, `Recent` — hiding empty sections) + compact dynamic starter strip or button.
   - Body: Lightweight 2-column (iPhone) / 3-column (iPad) or compact single-line clip cards showing `entry.title` (1 line) and optional secondary preview line, styled with `BrandAccent.color` and system adaptive keyboard background (no heavy blur layers to respect Jetsam RAM limits).
   - Tap inserts `entry.insertionText()` via `textDocumentProxy.insertText(_:)`, flashes a subtle accent highlight / `"Inserted"` badge for ~0.6 s (respecting Reduce Motion).
   - Bottom bar: Globe switcher button (if `needsInputModeSwitchKey`), `Pesto` label, Backspace, Return.

---

## 6. Settings, History Lock & Privacy Integration

1. **No new toggle required (or optional shared toggle copy update):**
   - `Setting.quickInsertEnabled` (*"Insert from Pesto in other apps"*) already produces and maintains `quick-insert.pestoquick`.
   - When `PestoKeyboard` is implemented, update the **AutoFill** section header/footer in `Sources/Mobile/SettingsView.swift` (e.g., section `"Other Apps"` or `"AutoFill & Keyboard"`) to mention both **AutoFill & Passwords** and **Keyboards > Add New Keyboard > Pesto**.
   - Keep `Setting.showsClipsOutsideWhileLocked` (*"Show clips in widgets and AutoFill while locked"* -> optionally *"Show clips in widgets, AutoFill, and keyboard while locked"* if desired, keeping the setting key unchanged).
2. **Auto-expiry / Clear History / Lock behavior:**
   - Already enforced by `MobileAppState+QuickInsert.swift`:
     - Leaving foreground rewrites the set immediately.
     - Clear History writes `QuickInsertSet.empty` immediately.
     - Turning off `Setting.quickInsertEnabled` deletes `quick-insert.pestoquick` and removes the quick-insert Keychain item.
     - Becoming locked (`historyLock.holdsOutsideSurfaces`) writes `QuickInsertSet.empty`.
3. **Memory & Security Guardrails:**
   - Enforce `QuickInsertPolicy.maxFileBytes` (2 MB) via `SealedGroupFile` before decryption.
   - Never log clip text, titles, or key material (`Logger` logs only error types, never content).
   - Add `MobileKeyboard` to `AccentUsageTests`, `VocabularyTests`, `LocalizationRoutingTests`, and `EntitlementsTests`.
   - Note on iOS distribution: Adding `net.copypesto.pesto.keyboard` requires a matching App ID and provisioning profile in Apple Developer Portal with **App Groups** (`group.net.copypesto.pesto`) enabled; Keychain Sharing (`keychain-access-groups`) is automatically authorized per-team by the provisioning profile.
   - Write an ADR when shipping `PestoKeyboard` to formally amend ADR 0046's "No keyboard extension" clause.

---

## 7. Implementation Checklist for `[Claude]`

1. Add `AppIdentity.keyboardBundleID` in `Sources/Core/Runtime/AppIdentity.swift`.
2. Create `Sources/MobileKeyboard/` with:
   - `Info.plist` (`com.apple.keyboard-service`, `RequestsOpenAccess = YES`, `PestoAppIdentifierPrefix = $(AppIdentifierPrefix)`)
   - `PestoKeyboard.entitlements` (app group + quick-insert keychain group alone)
   - `PrivacyInfo.xcprivacy` (no tracking, `CA92.1`, `C617.1`)
   - `KeyboardStarter.swift` / `KeyboardMenuModel.swift` (testable pure logic for starters & 4 states)
   - `KeyboardViewController.swift` & `KeyboardRootView.swift` (`UIInputViewController`, `UIHostingController`, explicit height constraint, `needsInputModeSwitchKey`, `hasFullAccess` reload)
3. Register `PestoKeyboard` in `Pesto.yml` and embed it in `PestoMobile`, then run `make generate`.
4. Update `EntitlementsTests.swift`, `MobileSubmissionTests.swift`, `VocabularyTests.swift`, `LocalizationRoutingTests.swift`, `AccentUsageTests.swift`, and add unit tests in `Tests/PestoMobileTests/` for `KeyboardMenuModel` & `KeyboardStarter` (restricted vs full access, `.unavailable` / `.empty` / `.ready`, starter expansion).
5. Update `SettingsView.swift` copy (and `ADR 0046` amendment ADR).

## 8. The keyboard after ADR 0066 (2026-11-25)
Sections 5.1–5.3 describe the first version; ADRs 0062, 0063 and 0066 supersede them where they differ.
- **Shelf:** the library's chips with a round search key beside them; a gear chip at the end of the row (no word,
  ADR 0074) opens settings inside the keyboard (`KeyboardSettingsPanel`: back to Clips, Keyboard Settings, an Open
  Pesto button; the size, with the person's own cards previewed at it in as many rows as the keyboard will show,
  `KeyboardSizePreview`). Pesto's own Keyboard & AutoFill page shows the same preview with sample clips, framed as
  the keyboard. Cards are the app's cards (`QuickInsertCardFace`): the app's icon leads the foot line and the foot
  glows in the app's color (ADRs 0068, 0074). iOS's bottom row: 123, globe (when iOS asks for it), space, delete, return. A word search rings its first
  match and Return reads Insert.
- **Search page:** the field, a tray of results (one row at Small and Medium, two at Large, one in landscape, five
  on iPad; `KeyboardSearchMetrics`), the letters of the person's own keyboards (`SearchKeyboardLayout`: 18 layouts,
  shift layers, long-press accents, Korean composed by `HangulComposer`), and 123, globe, a language key with the
  layout's two capitals when there are two or more (not a globe: iOS's globe leaves Pesto; ADR 0074), space (a hold
  also moves to the next layout) and Done. iPad puts Delete on the top row and Done on the middle row, with Shift on both sides.
- **Not typeable here:** Japanese and Chinese, which need an input method; the field's placeholder says so.
- **Touches on a card** go through one UIKit recognizer (`KeyboardPressRecognizer`, decided by `KeyboardPress`), not
  SwiftUI's `onTapGesture` and `onLongPressGesture`: those held a touch that started on a card until it had moved
  far enough, so reversing the row mid-glide stuck. The recognizer fails at the first movement past 10 pt and when the
  scroll view takes the touch; a picture card has no hold, so its context menu takes a long press. Keep new card
  gestures in it (`KeyboardCardActions`), never as SwiftUI gestures on the card.
