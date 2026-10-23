// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

struct ShortcutsSettings: View {
    @Environment(AppState.self) private var appState: AppState
    @AppStorage(Setting.doubleCopyAppend) private var doubleCopyAppend: Bool
    @State private var hotkeyConflicts: [String] = []
    @State private var isAXTrusted = AccessibilityAccess.isTrusted

    var body: some View {
        Group {
            shortcutsSection
            copyShortcutSection
            HistoryLockGate { PinnedShortcutsSection() }
            shelfKeysSection
        }
        .onReceive(NotificationCenter.default.publisher(for: .hotkeyConflictDetected)) { note in
            hotkeyConflicts = note.userInfo?["conflicts"] as? [String] ?? []
        }
        .onAppear {
            // Surface conflicts that were detected before this view appeared.
            hotkeyConflicts = appState.hotkeyController.conflictingHotkeys
            isAXTrusted = AccessibilityAccess.isTrusted
        }
    }

    private var shortcutsSection: some View {
        Section {
            if !hotkeyConflicts.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.statusWarning)
                        .accessibilityHidden(true)
                    let names = hotkeyConflicts.joined(separator: ", ")
                    Text(String(localized: "\(hotkeyConflicts.count) shortcut conflicts: \(names)"))
                        .font(.footnote)
                        .pestoQuiet()
                }
            }
            HotkeyRecorderField(shortcut: .openShelf).settingsRow("Open the shelf shortcut")
            HotkeyRecorderField(shortcut: .pastePrevious).settingsRow("Quick paste shortcut")
            HotkeyRecorderField(shortcut: .pastePlainText).settingsRow("Paste as plain text shortcut")
            HotkeyRecorderField(shortcut: .togglePinnedWindow).settingsRow("Floating window shortcut")
            HotkeyRecorderField(shortcut: .toggleCapture).settingsRow("Pause capturing shortcut")
            HotkeyRecorderField(shortcut: .toggleClipContents).settingsRow("Hide clip contents shortcut")
        } header: {
            Text("Everywhere")
        } footer: {
            Text(
                "Click a shortcut, then press the new keys. It needs ⌘, ⌥ or ⌃, and Esc cancels. " +
                    "Pesto pauses its own shortcuts while you record, so you can record the one you have now. " +
                    "A shortcut that shows no keys is off until you record one. ⇧⌘V is also Paste As in some apps: " +
                    "change it here if it clashes."
            )
            .pestoCaption()
        }
    }

    private var shelfKeysSection: some View {
        Section {
            ForEach(ShelfKeyReference.entries) { shelfKey in
                HStack(spacing: 4) {
                    Text(verbatim: shelfKey.action)
                    Spacer(minLength: 12)
                    ForEach(Array(shelfKey.keys.enumerated()), id: \.offset) { _, symbol in
                        Keycap(symbol: symbol)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(shelfKey.action), \(shelfKey.keys.joined(separator: " "))")
            }
        } header: {
            Text("On the shelf").settingsRow("Shelf keys")
        } footer: {
            Text("These work while the shelf is open. They are fixed, so they never clash with your own shortcuts.")
                .pestoCaption()
        }
    }

    private var copyShortcutSection: some View {
        Section {
            Toggle("Double-press ⌘C to append to the last clip", isOn: $doubleCopyAppend)
                .disabled(!isAXTrusted && !doubleCopyAppend)
                .accessibilityIdentifier(AccessibilityID.doubleCopyToggle)
                .settingsRow("Double-press ⌘C to append")
        } header: {
            Text("Copying")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    "Off by default: it watches every ⌘C keystroke system-wide and records only whether ⌘C was " +
                        "pressed twice within half a second."
                )
                if !isAXTrusted {
                    Text("It needs Accessibility, which is not granted yet (see General, Permissions).")
                }
            }
            .pestoCaption()
        }
    }
}

/// The pinned clips that have their own ⌃1 to ⌃9 shortcut, with a button to take a shortcut away. A shortcut is given
/// to
/// a clip from its card's menu; this is where they are all seen together.
private struct PinnedShortcutsSection: View {
    @Environment(AppState.self) private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<ClipboardItem> { $0.pinnedHotkeyIndex != nil },
        sort: [SortDescriptor(\ClipboardItem.pinnedHotkeyIndex)]
    ) private var shortcuts: [ClipboardItem]

    var body: some View {
        Section {
            if shortcuts.isEmpty {
                Text("No pinned clip has a shortcut yet.").foregroundStyle(.primary.opacity(0.7))
            }
            ForEach(shortcuts) { item in
                HStack {
                    Text("\u{2303}\(item.pinnedHotkeyIndex ?? 0)")
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                        .frame(width: 34, alignment: .leading)
                    Text(item.customTitle ?? String(item.gridPreview.prefix(60)))
                        .lineLimit(1)
                    Spacer()
                    Button("Remove") {
                        appState.clipEditor(context: modelContext).edit(item) { $0.pinnedHotkeyIndex = nil }
                    }
                    .accessibilityIdentifier(AccessibilityID.removePinnedShortcut(item.pinnedHotkeyIndex ?? 0))
                }
            }
        } header: {
            Text("Pinned clip shortcuts").settingsRow("Pinned clip shortcuts")
        } footer: {
            Text(
                "Right-click a pinned clip and choose a shortcut to paste it from any app with " +
                    "\u{2303}1 to \u{2303}9. Pesto claims a shortcut only while a clip uses it."
            )
            .pestoCaption()
        }
    }
}
