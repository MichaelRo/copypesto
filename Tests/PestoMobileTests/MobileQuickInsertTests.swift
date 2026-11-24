// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("The app keeps the AutoFill set in step with the history")
@MainActor
struct MobileQuickInsertTests {
    private let secret = "ghp_8fK2mQ9xLr4TzW7nB1vC6yH3sJ5dE0aGpU2i"

    private final class Switch {
        var isOn: Bool

        init(_ isOn: Bool) {
            self.isOn = isOn
        }
    }

    @MainActor
    private struct Fixture {
        let target: QuickInsertTarget
        let secrets: MemorySecrets
        let setting: Switch

        var file: QuickInsertFile {
            target.file
        }

        func read() throws -> QuickInsertSet {
            try file.read(with: #require(try target.keys.key()))
        }
    }

    private func fixture(on: Bool) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-mobile-quick-insert-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let secrets = MemorySecrets()
        let setting = Switch(on)
        let target = QuickInsertTarget(
            file: QuickInsertFile(root: root), keys: QuickInsertKeyStore(secrets: secrets), isEnabled: { setting.isOn }
        )
        return Fixture(target: target, secrets: secrets, setting: setting)
    }

    /// The texts of the set once the pending rewrite has run, waiting out saves that start a new one.
    private func written(_ fixture: Fixture) async throws -> [String] {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            let texts = try fixture.read().entries.map(\.text)
            if !texts.isEmpty { return texts }
            try await Task.sleep(for: .milliseconds(100))
        }
        return []
    }

    @Test("with the setting off there is no file and the Keychain is never asked")
    func whenOff_thenNoFileAndNoKey() async throws {
        let library = try await MobileTestLibrary()
        let fixture = try fixture(on: false)
        defer { try? FileManager.default.removeItem(at: fixture.file.root) }
        library.state.quickInsert = fixture.target
        try await library.add("a note")

        library.state.writeQuickInsert()
        library.state.didLeaveForeground()

        #expect(!fixture.file.exists)
        #expect(fixture.secrets.readCount == 0)
    }

    @Test("on, the set is written with the history's text; a secret is not in it")
    func whenOn_thenTheSetIsWritten() async throws {
        let library = try await MobileTestLibrary()
        let fixture = try fixture(on: true)
        defer { try? FileManager.default.removeItem(at: fixture.file.root) }
        library.state.quickInsert = fixture.target
        try await library.add("12 Basil Lane")
        try await library.service.ingest(#require(ClipCapture.text(secret)))
        try await library.refreshed()

        library.state.writeQuickInsert()

        #expect(try fixture.read().entries.map(\.text) == ["12 Basil Lane"])
        let bytes = try Data(contentsOf: fixture.file.url)
        #expect(bytes.range(of: Data("Basil".utf8)) == nil)
    }

    @Test("a change to the history is written after a moment, and leaving the foreground writes at once")
    func whenTheHistoryChanges_thenTheSetFollows() async throws {
        let library = try await MobileTestLibrary()
        let fixture = try fixture(on: true)
        defer { try? FileManager.default.removeItem(at: fixture.file.root) }
        library.state.quickInsert = fixture.target
        library.state.writeQuickInsert()
        #expect(try fixture.read().entries.isEmpty)

        try await library.add("first")
        #expect(try await written(fixture) == ["first"])

        try await library.add("second")
        library.state.didLeaveForeground()
        #expect(try fixture.read().entries.map(\.text) == ["second", "first"])
    }

    @Test("Clear History empties the set at once")
    func whenTheHistoryIsCleared_thenTheSetIsEmpty() async throws {
        let library = try await MobileTestLibrary()
        let fixture = try fixture(on: true)
        defer { try? FileManager.default.removeItem(at: fixture.file.root) }
        library.state.quickInsert = fixture.target
        try await library.add("to be cleared")
        library.state.writeQuickInsert()
        #expect(try fixture.read().entries.count == 1)

        await library.state.clearHistory()

        #expect(try fixture.read().entries.isEmpty)
    }

    @Test("a clip edited into a secret leaves the set on the next write")
    func whenAClipBecomesSecret_thenItLeavesTheSet() async throws {
        let library = try await MobileTestLibrary()
        let fixture = try fixture(on: true)
        defer { try? FileManager.default.removeItem(at: fixture.file.root) }
        library.state.quickInsert = fixture.target
        let item = try await library.add("harmless")
        library.state.writeQuickInsert()
        #expect(try fixture.read().entries.map(\.text) == ["harmless"])

        #expect(try await library.service.updateText(id: item.id, text: secret) == .saved)
        try await library.refreshed()
        #expect(try #require(library.store.item(for: item.id)).sensitivityRaw != nil)
        library.state.writeQuickInsert()

        #expect(try fixture.read().entries.isEmpty)
    }

    @Test("a set that cannot be written again is removed, never left with clips deleted or made secret since")
    func whenARewriteFails_thenTheOldSetIsRemoved() async throws {
        let library = try await MobileTestLibrary()
        let fixture = try fixture(on: true)
        defer { try? FileManager.default.removeItem(at: fixture.file.root) }
        library.state.quickInsert = fixture.target
        try await library.add("written while unlocked")
        library.state.writeQuickInsert()
        #expect(fixture.file.exists)

        fixture.secrets.refusesReads = true
        library.state.writeQuickInsert()

        #expect(!fixture.file.exists)
    }

    @Test("a deleted clip leaves the set at once, not after the rewrite's pause")
    func whenAClipIsDeleted_thenItLeavesTheSetAtOnce() async throws {
        let library = try await MobileTestLibrary()
        let fixture = try fixture(on: true)
        defer { try? FileManager.default.removeItem(at: fixture.file.root) }
        library.state.quickInsert = fixture.target
        let item = try await library.add("delete me")
        library.state.writeQuickInsert()
        #expect(try fixture.read().entries.map(\.text) == ["delete me"])

        await library.state.delete([item.id])

        #expect(try fixture.read().entries.isEmpty)
    }

    @Test("turning the setting off removes the file and the key")
    func whenTurnedOff_thenTheFileAndKeyGo() async throws {
        let library = try await MobileTestLibrary()
        let fixture = try fixture(on: true)
        defer { try? FileManager.default.removeItem(at: fixture.file.root) }
        library.state.quickInsert = fixture.target
        try await library.add("kept for a while")
        library.state.writeQuickInsert()
        #expect(fixture.file.exists)

        fixture.setting.isOn = false
        library.state.quickInsertSettingChanged()

        #expect(!fixture.file.exists)
        #expect(try fixture.target.keys.key() == nil)
    }

    @Test("the extension's path opens what the app wrote: the same file, the same shared key")
    func whenTheExtensionReads_thenItOpensTheAppsSet() async throws {
        let library = try await MobileTestLibrary()
        let fixture = try fixture(on: true)
        defer { try? FileManager.default.removeItem(at: fixture.file.root) }
        library.state.quickInsert = fixture.target
        try await library.add("Dear {{date}},")
        let pinned = try #require(library.store.items.first)
        await library.state.togglePin(pinned.id)
        try await library.refreshed()
        library.state.writeQuickInsert()

        let reader = QuickInsertKeyStore(secrets: fixture.secrets)
        let set = try QuickInsertFile(root: fixture.file.root).read(with: #require(try reader.key()))
        let menu = QuickInsertMenu(set: set)

        #expect(menu.state == .ready)
        #expect(menu.groups(matching: "").flatMap(\.entries).map(\.section) == [.snippets])
        #expect(menu.groups(matching: "", chip: .snippets).map(\.section) == [.snippets])
        #expect(try !#require(set.entries.first).insertionText().contains("{{"))
    }

    @Test("legacy quickInsertEnabled migrates once to keyboardEnabled and autoFillEnabled")
    func whenLegacyQuickInsertEnabled_thenMigratesToKeyboardAndAutoFill() {
        let defaults = ThrowawayDefaults.make()
        defaults.set(true, for: Setting.quickInsertEnabled)

        MobileAppState.migrateQuickInsertSettingsIfNeeded(defaults: defaults)

        #expect(defaults.value(for: Setting.keyboardEnabled))
        #expect(defaults.value(for: Setting.autoFillEnabled))
        #expect(defaults.value(for: Setting.quickInsertEnabled))

        defaults.set(false, for: Setting.keyboardEnabled)
        defaults.set(false, for: Setting.autoFillEnabled)
        defaults.set(false, for: Setting.quickInsertEnabled)
        MobileAppState.migrateQuickInsertSettingsIfNeeded(defaults: defaults)

        #expect(!defaults.value(for: Setting.keyboardEnabled))
        #expect(!defaults.value(for: Setting.autoFillEnabled))
    }

    @Test("when only AutoFill is enabled, the set is written for AutoFill while the keyboard menu stays unavailable")
    func whenOnlyAutoFillEnabled_thenKeyboardMenuIsUnavailable() async throws {
        let library = try await MobileTestLibrary()
        let fixture = try fixture(on: true)
        defer { try? FileManager.default.removeItem(at: fixture.file.root) }
        var target = fixture.target
        target.options = {
            QuickInsertSelection.Options(keyboardEnabled: false)
        }
        library.state.quickInsert = target
        try await library.add("12 Basil Lane")

        library.state.writeQuickInsert()

        let set = try fixture.read()
        #expect(set.entries.map(\.text) == ["12 Basil Lane"])
        #expect(!set.keyboardEnabled)
        #expect(KeyboardMenu(hasFullAccess: true) { set }.state == .unavailable)
    }

    @Test("reconcileKeyboardSize updates Setting.keyboardSize and rewrites the quick-insert set")
    func whenKeyboardSizeSavedInGroup_thenAppReconcilesAndRewrites() async throws {
        let library = try await MobileTestLibrary()
        let fixture = try fixture(on: true)
        defer { try? FileManager.default.removeItem(at: fixture.file.root) }
        let defaults = ThrowawayDefaults.make()
        var target = fixture.target
        target.options = {
            QuickInsertSelection.Options(
                keyboardSize: KeyboardSize(rawValue: defaults.value(for: Setting.keyboardSize)) ?? .medium
            )
        }
        library.state.quickInsert = target

        let store = KeyboardSizeStore(root: fixture.file.root)
        try store.save(.large)

        library.state.reconcileKeyboardSize(defaults: defaults, store: store)

        #expect(defaults.value(for: Setting.keyboardSize) == KeyboardSize.large.rawValue)
        #expect(try fixture.read().keyboardSize == .large)
    }

    @Test("Clear History keeps the user's accent and keyboardSize in the empty QuickInsertSet")
    func whenCleared_thenQuickInsertRetainsThemeAndSize() async throws {
        let library = try await MobileTestLibrary()
        let fixture = try fixture(on: true)
        defer { try? FileManager.default.removeItem(at: fixture.file.root) }
        var target = fixture.target
        let theme = WidgetSnapshot.Theme.resolve(accent: "blue", theme: "parmesan", darkTheme: "")
        target.options = {
            QuickInsertSelection.Options(keyboardSize: .large, accent: theme)
        }
        library.state.quickInsert = target
        try await library.add("Clear me")
        library.state.writeQuickInsert()

        await library.state.clearHistory()

        let cleared = try fixture.read()
        #expect(cleared.entries.isEmpty)
        #expect(cleared.keyboardSize == .large)
        #expect(cleared.accent == theme)
    }
}
