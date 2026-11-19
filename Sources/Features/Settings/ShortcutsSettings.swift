// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

struct ShortcutsSettings: View {
    @Environment(AppState.self) private var appState: AppState
    @State private var hotkeyConflicts: [String] = []
    @State private var showingReferenceSheet = false

    var body: some View {
        Group {
            shortcutsSection
            HistoryLockGate { PinnedShortcutsSection() }
            shelfKeysSection
        }
        .onReceive(NotificationCenter.default.publisher(for: .hotkeyConflictDetected)) { note in
            hotkeyConflicts = note.userInfo?["conflicts"] as? [String] ?? []
        }
        .onAppear {
            // Surface conflicts that were detected before this view appeared.
            hotkeyConflicts = appState.hotkeyController.conflictingHotkeys
        }
        .sheet(isPresented: $showingReferenceSheet) {
            ShelfKeysReferenceSheet()
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
            HotkeyRecorderField(shortcut: .pastePlainText).settingsRow("Paste as plain text shortcut")
            HotkeyRecorderField(shortcut: .pastePrevious).settingsRow("Quick paste shortcut")
            HotkeyRecorderField(shortcut: .togglePinnedWindow).settingsRow("Floating window shortcut")
            HotkeyRecorderField(shortcut: .toggleCapture).settingsRow("Pause capturing shortcut")
            HotkeyRecorderField(shortcut: .toggleClipContents).settingsRow("Hide clip contents shortcut")
        } header: {
            Text("Everywhere")
        } footer: {
            HStack(spacing: 6) {
                Text("Click a shortcut, then press the new keys. Esc cancels.")
                    .pestoCaption()
                InfoPopoverButton(
                    "Global shortcuts",
                    message: """
                    Click a shortcut, then press the new keys. It needs \u{2318}, \u{2325} or \u{2303}, and Esc \
                    cancels. Pesto pauses its own shortcuts while you record, so you can record the one you have \
                    now. A shortcut that shows no keys is off until you record one. \u{21E7}\u{2318}V is also Paste \
                    As in some apps: change it here if it clashes.
                    """
                )
            }
        }
    }

    private struct ShelfKeyPair: Identifiable {
        let id: Int
        let left: ShelfKey
        let right: ShelfKey?
    }

    private static let shelfKeyPairs: [ShelfKeyPair] = {
        let entries = ShelfKeyReference.entries
        return stride(from: 0, to: entries.count, by: 2).map { index in
            ShelfKeyPair(id: index, left: entries[index], right: index + 1 < entries.count ? entries[index + 1] : nil)
        }
    }()

    private var shelfKeysSection: some View {
        Section {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Self.shelfKeyPairs) { pair in
                        HStack(spacing: 20) {
                            shelfKeyCell(pair.left)
                            if let right = pair.right {
                                shelfKeyCell(right)
                            } else {
                                Spacer(minLength: 0).frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 175)
        } header: {
            HStack {
                Text("On the shelf").settingsRow("Shelf keys")
                Spacer()
                Button("Full Reference\u{2026}") { showingReferenceSheet = true }
                    .controlSize(.small)
            }
        } footer: {
            Text("These work while the shelf is open. They are fixed, so they never clash with your own shortcuts.")
                .pestoCaption()
        }
    }

    private func shelfKeyCell(_ shelfKey: ShelfKey) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: shelfKey.action)
                .lineLimit(1)
            Spacer(minLength: 8)
            ForEach(Array(shelfKey.keys.enumerated()), id: \.offset) { _, symbol in
                Keycap(symbol: symbol)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .drawingGroup()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(shelfKey.action), \(shelfKey.keys.joined(separator: " "))")
        .accessibilityAddTraits(.isStaticText)
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
            } else if shortcuts.count > 3 {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(shortcuts) { shortcutRow($0) }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 84)
            } else {
                ForEach(shortcuts) { shortcutRow($0) }
            }
        } header: {
            Text("Pinned clip shortcuts").settingsRow("Pinned clip shortcuts")
        } footer: {
            HStack(spacing: 6) {
                Text("Right-click a pinned clip to assign \u{2303}1 to \u{2303}9.").pestoCaption()
                InfoPopoverButton(
                    "Pinned clip shortcuts",
                    message: """
                    Right-click a pinned clip and choose a shortcut to paste it from any app with \u{2303}1 to \
                    \u{2303}9. Pesto claims a shortcut only while a clip uses it.
                    """
                )
            }
        }
    }

    private func shortcutRow(_ item: ClipboardItem) -> some View {
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
            .controlSize(.small)
            .accessibilityIdentifier(AccessibilityID.removePinnedShortcut(item.pinnedHotkeyIndex ?? 0))
        }
    }
}

private struct ShelfKeysReferenceSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("On the shelf").font(.headline)
                Text("These work while the shelf is open. They are fixed, so they never clash with your own shortcuts.")
                    .pestoCaption()
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(ShelfKeyReference.entries.enumerated()), id: \.offset) { _, shelfKey in
                        HStack(alignment: .center, spacing: 12) {
                            Text(verbatim: shelfKey.action)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 4) {
                                ForEach(Array(shelfKey.keys.enumerated()), id: \.offset) { _, symbol in
                                    Keycap(symbol: symbol)
                                }
                            }
                        }
                        Divider()
                    }
                }
                .padding(.vertical, 4)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.pestoProminent)
            }
        }
        .padding(20)
        .frame(width: 440, height: 480)
    }
}
