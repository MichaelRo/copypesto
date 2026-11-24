# 0046. Pesto runs on iPhone and iPad as one more sync device; Core is shared, not copied

Status: Accepted (owner request, 2026-11-14); its "No keyboard extension" is amended by ADR 0061, which adds an optional keyboard with no typing keys that reads only the quick-insert set, and by ADR 0063, which adds on-device search

Extends ADR 0002 (sealed at rest), ADR 0007 (Core is a one-way graph of directories) and ADR 0018 (sync through per-device logs in a folder). Nothing they decide is reversed.

## Context
Pesto was a Mac app only. `PestoCore` declared macOS alone, held no `#if os(…)`, and about 85 of its 450 files used AppKit, Carbon, Accessibility or FSEvents. A few types that have nothing to do with the Mac lived in those files (`PasteboardCapture` beside the watcher, `SourceAppRecord` beside the resolver, `ChangeCounting` beside the pasteboard reader).

Checked while deciding:
- The models, `StorageService`, `StorageBoot`, `HistoryStore`, `HistoryIndex`, `ClipEditor`, `CollectionStore`, `SyncController`, the History Lock, the predicate rules, search and the AI actions import nothing from AppKit.
- The sync format carries no platform field and nothing that requires a Mac. What is Mac-only around it: the default folder (a path under the home folder), the FSEvents watcher, the `SecTask` entitlement check and the wording.
- iOS gives an app no clipboard in the background, and tells the person each time an app reads it.
- Only the iOS 27 simulator runtime is installed where Pesto is built.

## Decision
**One iOS app for iPhone and iPad** (one target, both device families), minimum iOS 26. An older iOS could not be tested, and iOS 26 has the on-device model and the glass materials without a second code path.

**Core is one module for both platforms.** `Package.swift` declares macOS 15 and iOS 26. A file that only a Mac can run is wrapped whole in `#if os(macOS)`; a file both can run keeps only its platform calls inside `#if`. There is no second "Core for Mac" module: it would cut `internal` access across Core and redraw the directory graph for no gain. `PlatformFenceTests` fails on a platform import outside `#if os(…)` and on a Core directory whose count of Mac-only files grows.

**What iOS does without, said plainly:** watching the clipboard, global shortcuts, pasting into another app, importers for other Mac clipboard apps, the settings and history backup file, rich-text (RTF) snippet expansion, and a picture for an SVG clip (iOS has no public SVG rasterizer). A snippet's `{{clipboard}}` is filled only by a caller that asked the person first.

**The iOS app is a sync device** with its own store and its own history key (ADR 0002 is unchanged: the history key never leaves a device). It joins the same folder as the Macs.
- **Folder:** the person picks it once in the system file picker and the app keeps a security-scoped bookmark. A shared iCloud container was not chosen: it needs an iCloud entitlement on the Mac app, and it would move the folder of everyone who syncs today.
- **Key:** the iOS app has the Mac app's bundle identifier, so the sync key in iCloud Keychain (ADR 0018) is in its Keychain group too. The recovery key and the eight-word approval (ADR 0039) work as on a Mac. A simulator has no iCloud Keychain, so there the key is a this-device item.
- **Changes in the folder** are heard through a file presenter, with the same poll as a fallback.

**Capture on iOS is always something the person does:** the system Paste button, a new note, a drop, the share sheet, a Shortcuts action. Every one goes through `StorageService.ingest` (ADR 0011).

**The Mac views are not ported.** The iOS interface is written for iOS on the shared state above. A view both platforms use lives in `Sources/Features/Common`; nothing is copied.

**No keyboard extension.** It can reach an app's data only with Full Access, which the system describes as letting the developer see everything typed; it would hold a key that opens clips inside a process that sees every keystroke; and it runs under a tight memory limit. Inserting a clip into another app is offered through AutoFill's text insertion instead, which needs none of that.

## Consequences
- A change to Core is built for both platforms. A new Core file that imports AppKit must say so with `#if os(macOS)`.
- The source app of a clip cannot be looked up on iOS (`UnknownSourceApps`); a synced clip keeps the name it arrived with.
- iOS distribution is TestFlight and the App Store; the Mac app stays a Developer ID download. Every feature stays free on both (ADR 0001).
- The arrival of the sync key on a real iPhone, and the file picker against a real iCloud Drive, are hand checks: a simulator can show neither.

## Docs affected
`AGENTS.md` (platforms, module boundaries, pitfalls), `docs/development.md`, `docs/testing.md`, `README.md`, `docs/guide/moving-from.md`, the privacy guide. The website says nothing about an iPhone app until one is released.
