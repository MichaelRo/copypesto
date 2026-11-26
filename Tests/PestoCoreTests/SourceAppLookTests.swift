// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

/// The keyboard, AutoFill and the widgets draw a clip's card as Pesto does, with its app's icon and the foot glow in
/// the app's color (ADR 0074), so the two sealed files carry each clip's app and color, and each app's icon once.
@Suite("The sealed sets carry each clip's app and color, and the apps' icons")
@MainActor
struct SourceAppLookTests {
    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(repeating: 7, count: 200)

    private static func icon(size: Int) -> Data {
        png + Data(repeating: 1, count: max(0, size - png.count))
    }

    @discardableResult
    private static func item(
        _ context: ModelContext, bundleID: String?, color: String?, remote: Bool = false, at seconds: Double
    )
    -> ClipboardItem {
        let item = ClipboardItem(
            type: .text, sourceBundleID: bundleID, sourceDominantColorHex: color, previewText: "",
            contentHash: UUID().uuidString, byteSize: 5, deviceID: "t", sequenceNumber: Int64(seconds)
        )
        item.timestamp = Date(timeIntervalSince1970: 1_800_000_000 + seconds)
        item.isRemote = remote
        context.insert(item)
        return item
    }

    @Test("a clip's look is its app and its sampled color; a clip from another device's clipboard has neither")
    func whenRead_thenLocalClipsCarryTheirApp() throws {
        let context = try ModelContext(ModelContainerSetup.makeInMemory())
        let local = Self.item(context, bundleID: "com.apple.Notes", color: "#F5C400", at: 1)
        let remote = Self.item(context, bundleID: "com.apple.Notes", color: "#F5C400", remote: true, at: 2)
        #expect(local.sourceAppLook == SourceAppLook(bundleID: "com.apple.Notes", colorHex: "#F5C400"))
        #expect(remote.sourceAppLook == SourceAppLook(bundleID: nil, colorHex: nil))
    }

    @Test("only a #RRGGBB color that is not the placeholder grey is kept")
    func whenColorIsOdd_thenDropped() {
        #expect(SourceAppLook(bundleID: "a", colorHex: "#2e7d4f").colorHex == "#2E7D4F")
        #expect(SourceAppLook(bundleID: "a", colorHex: "#888888").colorHex == nil)
        #expect(SourceAppLook(bundleID: "a", colorHex: "red").colorHex == nil)
        #expect(SourceAppLook(bundleID: "a", colorHex: "#12345").colorHex == nil)
        #expect(SourceAppLook(bundleID: " ", colorHex: nil).bundleID == nil)
    }

    @Test("icons are collected once per app, in order, PNG only, within the count and byte caps")
    func whenCollected_thenBounded() {
        let icons: [String: Data] = [
            "a": Self.icon(size: 1000), "b": Data("not a png".utf8), "c": Self.icon(size: 9000),
            "d": Self.icon(size: 3000), "e": Self.icon(size: 3000)
        ]
        let collected = SourceAppIcons.collect(
            for: ["a", nil, "a", "b", "c", "d", "e"], maxApps: 3, maxBytes: 4500, icon: { icons[$0] }
        )
        #expect(Set(collected.keys) == ["a", "d"])
        let few = SourceAppIcons.collect(for: ["a", "d", "e"], maxApps: 2, maxBytes: 100_000, icon: { icons[$0] })
        #expect(Set(few.keys) == ["a", "d"])
    }

    @Test("quick-insert entries carry the app and color, and the set the icons of the apps it lists")
    func whenQuickInsertSetIsMade_thenItCarriesLooks() throws {
        let context = try ModelContext(ModelContainerSetup.makeInMemory())
        Self.item(context, bundleID: "com.apple.Notes", color: "#F5C400", at: 1)
        Self.item(context, bundleID: "com.apple.Safari", color: nil, at: 2)
        try context.save()
        let set = try QuickInsertSelection.set(
            in: context, now: .now,
            reader: QuickInsertSelection.Reader(text: { _ in "hello" })
        )
        .attachingAppIcons { $0 == "com.apple.Notes" ? Self.icon(size: 500) : nil }
        let notes = try #require(set.entries.first { $0.sourceBundleID == "com.apple.Notes" })
        #expect(notes.sourceColorHex == "#F5C400")
        #expect(set.entries.contains { $0.sourceBundleID == "com.apple.Safari" && $0.sourceColorHex == nil })
        #expect(Set(set.appIcons.keys) == ["com.apple.Notes"])
        #expect(set.appIcons.values.reduce(0) { $0 + $1.count } <= QuickInsertPolicy.maxAppIconBytes)
    }

    @Test("a set written before icons opens with none, and one with icons survives a round trip")
    func whenDecoded_thenOldAndNewFilesOpen() throws {
        let oldEntry: [String: Any] = [
            "id": UUID().uuidString, "section": "recent", "kind": "text", "title": "a", "text": "a",
            "expandsOnInsert": false
        ]
        let old = try JSONSerialization.data(withJSONObject: ["createdAt": 0, "entries": [oldEntry]])
        let decoded = try JSONDecoder().decode(QuickInsertSet.self, from: old)
        #expect(decoded.appIcons.isEmpty)
        #expect(decoded.entries.first?.sourceBundleID == nil)
        #expect(decoded.entries.first?.sourceColorHex == nil)

        let entry = QuickInsertEntry(
            id: UUID(), section: .recent, kind: .text, title: "a", text: "a", expandsOnInsert: false,
            sourceBundleID: "x", sourceColorHex: "#112233"
        )
        let set = QuickInsertSet(createdAt: .now, entries: [entry], appIcons: ["x": Self.png])
        let again = try JSONDecoder().decode(QuickInsertSet.self, from: JSONEncoder().encode(set))
        #expect(again == set)
        #expect(set.withExpiresAt(.now).appIcons == set.appIcons)
    }

    @Test("the keyboard and AutoFill menus hand over the icons, and none while locked or without Full Access")
    func whenMenusOpen_thenIconsFollowTheState() {
        let entry = QuickInsertEntry(
            id: UUID(), section: .recent, kind: .text, title: "a", text: "a", expandsOnInsert: false,
            sourceBundleID: "x"
        )
        let set = QuickInsertSet(createdAt: .now, entries: [entry], appIcons: ["x": Self.png])
        let locked = QuickInsertSet(createdAt: .now, entries: [entry], isLocked: true, appIcons: ["x": Self.png])
        #expect(KeyboardMenu(hasFullAccess: true) { set }.appIcons == ["x": Self.png])
        #expect(KeyboardMenu(hasFullAccess: true) { locked }.appIcons.isEmpty)
        #expect(KeyboardMenu(hasFullAccess: false) { set }.appIcons.isEmpty)
        #expect(QuickInsertMenu(set: set).appIcons == ["x": Self.png])
        #expect(QuickInsertMenu(set: locked).appIcons.isEmpty)
    }

    @Test("widget clips carry the app and color, and the snapshot the icons of the apps it shows")
    func whenWidgetSnapshotIsMade_thenItCarriesLooks() throws {
        let context = try ModelContext(ModelContainerSetup.makeInMemory())
        Self.item(context, bundleID: "com.apple.Notes", color: "#F5C400", at: 1)
        try context.save()
        let snapshot = try WidgetSnapshotSelection.snapshot(
            in: context, now: .now, theme: .brand,
            reader: WidgetSnapshotSelection.Reader(source: { _ in "Notes" })
        )
        .attachingAppIcons { _ in Self.icon(size: 500) }
        let clip = try #require(snapshot.clips.first)
        #expect(clip.sourceBundleID == "com.apple.Notes")
        #expect(clip.sourceColorHex == "#F5C400")
        #expect(Set(snapshot.appIcons.keys) == ["com.apple.Notes"])
        #expect(snapshot.withExpiresAt(nil).appIcons == snapshot.appIcons)

        let old = try JSONEncoder().encode(WidgetSnapshot(createdAt: .now, theme: .brand, clips: []))
        #expect(try JSONDecoder().decode(WidgetSnapshot.self, from: old).appIcons.isEmpty)
    }
}
