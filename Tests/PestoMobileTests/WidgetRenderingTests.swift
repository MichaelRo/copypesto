// SPDX-License-Identifier: MIT
import Foundation
import SwiftUI
import Testing
import UIKit
import WidgetKit
@testable import PestoCore
@testable import PestoMobile

/// Draws every family in every state, light and dark, the way the Home Screen frames it, and writes the pictures to
/// `.build/widget-renders` beside the repository so a person (or an agent) can look at them.
@Suite("The widget draws each family and state")
@MainActor
struct WidgetRenderingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build/widget-renders", isDirectory: true)

    private static let sizes: [WidgetSize: CGSize] = [
        .small: CGSize(width: 170, height: 170), .medium: CGSize(width: 364, height: 170),
        .large: CGSize(width: 364, height: 382)
    ]

    private func picture(width: CGFloat, height: CGFloat) throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { context in
            UIColor(red: 0.35, green: 0.55, blue: 0.3, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor(red: 0.95, green: 0.8, blue: 0.3, alpha: 1).setFill()
            let side = min(width, height) * 0.55
            context.cgContext.fillEllipse(in: CGRect(
                x: (width - side) / 2,
                y: (height - side) / 2,
                width: side,
                height: side
            ))
        }
        return try #require(image.jpegData(compressionQuality: 0.7))
    }

    private func snapshot() throws -> WidgetSnapshot {
        let clips = try [
            WidgetClip(
                id: UUID(), kind: .text, text: "Pick up basil, pine nuts and parmesan on the way home, and call Ana",
                source: "Notes", date: now - 40
            ),
            WidgetClip(
                id: UUID(), kind: .url, text: "https://copypesto.net/guide/sync", linkHost: "copypesto.net",
                linkPath: "/guide/sync", source: "Safari", date: now - 300
            ),
            WidgetClip(
                id: UUID(),
                kind: .color,
                text: "#2F8B4C",
                colorHex: "2F8B4C",
                source: "Pasted",
                date: now - 900
            ),
            WidgetClip(
                id: UUID(), kind: .image, text: "Basil on the sill", source: "Photos", date: now - 4000,
                thumbnail: picture(width: 240, height: 180)
            ),
            WidgetClip(
                id: UUID(), kind: .code, text: "let pesto = basil + garlic + oil", source: "Xcode", date: now - 9000,
                isPinned: true
            ),
            WidgetClip(id: UUID(), kind: .text, text: "12 Basil Lane", source: "Another device", date: now - 90_000),
            WidgetClip(
                id: UUID(), kind: .image, text: "Panorama", source: "Photos", date: now - 95_000,
                thumbnail: picture(width: 240, height: 80)
            ),
            WidgetClip(
                id: UUID(), kind: .file, text: "recipe.pdf", source: "Finder", date: now - 100_000
            )
        ]
        return WidgetSnapshot(createdAt: now, theme: .brand, clips: clips, pinned: [clips[4]])
    }

    @discardableResult
    private func render(_ entry: RecentClipsEntry, _ size: WidgetSize, dark: Bool, name: String) throws -> UIImage {
        let frame = try #require(Self.sizes[size])
        let content = WidgetContent(snapshot: entry.snapshot, size: size, source: entry.source)
        let palette = WidgetPalette(theme: content.theme, isDark: dark)
        let single = size == .small ? content.clips.first : nil
        let view = RecentClipsView(entry: entry, size: size)
            .padding(16)
            .frame(width: frame.width, height: frame.height)
            .background { RecentClipsView.ground(single: single, palette: palette) }
            .clipShape(.rect(cornerRadius: 22, style: .continuous))
            .padding(12)
            .background(dark ? Color.black : Color(white: 0.85))
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.uiImage)
        try FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)
        try #require(image.pngData()).write(to: Self.output.appendingPathComponent("\(name).png"))
        return image
    }

    @Test("every family, with clips, empty and unavailable, in light and dark, draws at its size")
    func whenDrawn_thenEveryFamilyAndStateRenders() throws {
        let full = try snapshot()
        let states: [(String, WidgetSnapshot?)] = [
            ("clips", full), ("empty", .empty(theme: .brand, at: now)), ("locked", .locked(theme: .brand, at: now)),
            ("unavailable", nil)
        ]
        for (state, snapshot) in states {
            for size in WidgetSize.allCases {
                for dark in [false, true] {
                    let name = "\(size)-\(state)-\(dark ? "dark" : "light")"
                    let image = try render(
                        RecentClipsEntry(date: now, snapshot: snapshot),
                        size,
                        dark: dark,
                        name: name
                    )
                    let frame = try #require(Self.sizes[size])
                    #expect(image.size.width == frame.width + 24, "\(name)")
                }
            }
        }
        for (index, name) in [
            (0, "text"), (1, "link"), (2, "color"), (3, "picture"), (4, "code"), (6, "panorama"), (7, "file")
        ] {
            let one = WidgetSnapshot(createdAt: now, theme: .brand, clips: [full.clips[index]])
            for dark in [false, true] {
                try render(
                    RecentClipsEntry(date: now, snapshot: one), .small, dark: dark,
                    name: "small-\(name)-\(dark ? "dark" : "light")"
                )
            }
        }
        let copied = RecentClipsEntry(date: now, snapshot: full, copiedID: full.clips[1].id)
        try render(copied, .medium, dark: false, name: "medium-copied-light")
        try render(
            RecentClipsEntry(date: now, snapshot: full, source: .pinned),
            .medium,
            dark: true,
            name: "medium-pinned-dark"
        )
        let noPins = WidgetSnapshot(createdAt: now, theme: .brand, clips: full.clips)
        try render(
            RecentClipsEntry(date: now, snapshot: noPins, source: .pinned),
            .small,
            dark: false,
            name: "small-nopins-light"
        )
    }

    @Test("a widget set to a collection draws its clips, its empty state and Choose a collection, in every family")
    func whenSetToACollection_thenItsStatesRender() throws {
        let full = try snapshot()
        let only = WidgetClip(id: UUID(), kind: .text, text: "Ana's number: call after six", date: now - 600)
        let work = WidgetCollection(id: UUID(), name: "Work", symbolName: "briefcase", colorHex: "#2F8B4C")
        let links = WidgetCollection(
            id: UUID(), name: "Links", symbolName: "link", colorHex: "#1E5AA8", isSmart: true
        )
        let empty = WidgetCollection(id: UUID(), name: "Later", symbolName: "clock", colorHex: "#8A4F16")
        let snapshot = WidgetSnapshot(
            createdAt: now, theme: .brand, clips: full.clips, pinned: full.pinned, collections: [work, links, empty],
            collectionClipIDs: [work.id: [only.id, full.clips[1].id, full.clips[3].id], links.id: [], empty.id: []],
            collectionClips: [only]
        )
        let cases: [String: (source: WidgetClipSource, state: WidgetContent.State)] = [
            "collection": (.collection(work.id), .clips), "collection-empty": (.collection(empty.id), .empty),
            "collection-smart-empty": (.collection(links.id), .empty),
            "collection-unchosen": (.collection(nil), .noCollection),
            "collection-deleted": (.collection(UUID()), .noCollection)
        ]
        for (name, (source, state)) in cases {
            for size in WidgetSize.allCases {
                #expect(WidgetContent(snapshot: snapshot, size: size, source: source).state == state, "\(name)")
                for dark in [false, true] {
                    let label = "\(size)-\(name)-\(dark ? "dark" : "light")"
                    let image = try render(
                        RecentClipsEntry(date: now, snapshot: snapshot, source: source), size, dark: dark, name: label
                    )
                    let frame = try #require(Self.sizes[size])
                    #expect(image.size.width == frame.width + 24, "\(label)")
                }
            }
        }
        let shown = WidgetContent(snapshot: snapshot, size: .large, source: .collection(work.id))
        #expect(shown.clips.map(\.text) == [
            "Ana's number: call after six",
            "https://copypesto.net/guide/sync",
            "Basil on the sill"
        ])
        let timeline = RecentClipsProvider.timeline(snapshot: snapshot, now: now, source: .collection(work.id))
        #expect(timeline.entries.allSatisfy { $0.source == .collection(work.id) })

        let entity = WidgetCollectionEntity(work)
        #expect(RecentClipsConfiguration(tapAction: .copy, source: .collection, collection: entity).clipSource
            == .collection(work.id))
        #expect(RecentClipsConfiguration(tapAction: .copy, source: .collection).clipSource == .collection(nil))
        #expect(RecentClipsConfiguration(tapAction: .copy, source: .pinned, collection: entity).clipSource == .pinned)
    }

    @Test("the timeline is one opened snapshot with an entry each time an age changes, and none to wait for when empty")
    func whenTheTimelineIsMade_thenItFollowsTheAges() throws {
        let timeline = try RecentClipsProvider.timeline(snapshot: snapshot(), now: now)
        let empty = RecentClipsProvider.timeline(snapshot: .empty(theme: .brand, at: now), now: now)

        #expect(timeline.entries.first?.date == now)
        #expect(timeline.entries.count == 61)
        #expect(timeline.entries.dropFirst().first?.date == now + 20)
        #expect(empty.entries.count == 1)
    }

    @Test("after an in-place copy the tile says Copied until the feedback ends, then the timeline goes on")
    func whenATileCopied_thenTheTimelineEndsItsCopied() {
        let id = UUID()
        let copiedAt = now - 0.5
        let timeline = RecentClipsProvider.timeline(
            snapshot: .empty(theme: .brand, at: now), now: now, copied: (id, copiedAt)
        )

        #expect(timeline.entries.map(\.copiedID) == [id, nil])
        #expect(timeline.entries.last?.date == copiedAt + WidgetSnapshotPolicy.copiedFeedback)
    }

    @Test("each tap action reaches the tile: Copy copies in place with the whole text, else it opens Pesto")
    func whenConfigured_thenEachTileTakesItsTap() throws {
        let clips = try snapshot().clips
        let whole = WidgetClip(id: UUID(), kind: .text, text: "short", fullText: "short", date: now)

        #expect(WidgetTap.decide(for: whole, action: .copy, copiesInPlace: CopyClipIntent.copiesInPlace)
            == (CopyClipIntent.copiesInPlace ? .copyInPlace(whole.id) : .link(WidgetLink.url(for: whole.id))))
        #expect(WidgetTap
            .decide(for: clips[3], action: .copy, copiesInPlace: true) == .link(WidgetLink.url(for: clips[3].id)))
        #expect(WidgetClipSpeech.hint(.copyInPlace(whole.id), kind: .text) == "Copies this clip")
        #expect(WidgetClipSpeech.hint(.link(WidgetLink.url(for: clips[1].id, action: .open)), kind: .url)
            == "Opens this link")
        #expect(WidgetClipSpeech.hint(.link(WidgetLink.url(for: clips[3].id)), kind: .image)
            == "Opens Pesto and copies this clip")
    }

    @Test("VoiceOver hears the kind, the content, the source, the age and the pin of a clip")
    func whenSpoken_thenTheLabelSaysWhatTheCardSays() throws {
        let clips = try snapshot().clips

        #expect(WidgetClipSpeech.label(clips[1], now: now) == "Link, copypesto.net, Safari, 5 minutes ago")
        #expect(WidgetClipSpeech.label(clips[2], now: now).hasPrefix("Color, #2F8B4C, Pasted"))
        #expect(WidgetClipSpeech.label(clips[4], now: now).hasSuffix("Pinned"))
        #expect(WidgetClipSpeech.foot(clips[0], now: now) == "Notes \u{00B7} just now")
    }

    @Test("Lock Screen accessory families render opt-in-off, locked, empty, and clip states")
    func whenLockScreenDrawn_thenAllAccessoryFamiliesRender() throws {
        struct FamilyCase {
            let family: WidgetFamily
            let size: CGSize
            let label: String
        }

        let full = try snapshot()
        let families = [
            FamilyCase(family: .accessoryCircular, size: CGSize(width: 60, height: 60), label: "circular"),
            FamilyCase(family: .accessoryRectangular, size: CGSize(width: 172, height: 72), label: "rectangular"),
            FamilyCase(family: .accessoryInline, size: CGSize(width: 240, height: 28), label: "inline")
        ]
        let entries: [(String, LockScreenClipsEntry)] = [
            ("optout", LockScreenClipsEntry(date: now, snapshot: full, showsClipsOnLockScreen: false)),
            ("clip", LockScreenClipsEntry(date: now, snapshot: full, showsClipsOnLockScreen: true)),
            ("locked", LockScreenClipsEntry(
                date: now, snapshot: .locked(theme: .brand, at: now), showsClipsOnLockScreen: true
            )),
            ("empty", LockScreenClipsEntry(
                date: now, snapshot: .empty(theme: .brand, at: now), showsClipsOnLockScreen: true
            )),
            ("unavailable", LockScreenClipsEntry(date: now, snapshot: nil, showsClipsOnLockScreen: true)),
            ("hidden", LockScreenClipsEntry(
                date: now, snapshot: .hidden(theme: .brand, at: now), showsClipsOnLockScreen: true
            )),
            ("nocollection", LockScreenClipsEntry(
                date: now, snapshot: full, showsClipsOnLockScreen: true, source: .collection(nil)
            ))
        ]
        #expect(!LockScreenClipsConfiguration().showsClipsOnLockScreen)
        for (state, entry) in entries {
            for item in families {
                let view = LockScreenClipsView(entry: entry, familyOverride: item.family)
                    .frame(width: item.size.width, height: item.size.height)
                    .background(Color.black)
                    .environment(\.colorScheme, .dark)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try #require(renderer.uiImage, "lockscreen-\(item.label)-\(state)")
                #expect(image.size.width == item.size.width)
                #expect(image.size.height == item.size.height)
            }
        }

        let expiry = now + 120
        let expiring = full.withExpiresAt(expiry)
        let timeline = LockScreenClipsProvider.timeline(
            snapshot: expiring, now: now, showsClipsOnLockScreen: true
        )
        #expect(timeline.entries.contains { $0.date == expiry })
        let optOutTimeline = LockScreenClipsProvider.timeline(
            snapshot: full, now: now, showsClipsOnLockScreen: false
        )
        #expect(optOutTimeline.entries.count == 1)

        let work = WidgetCollection(id: UUID(), name: "Work", symbolName: "briefcase", colorHex: "#2F8B4C")
        let entity = WidgetCollectionEntity(work)
        #expect(
            LockScreenClipsConfiguration(
                showsClipsOnLockScreen: true, source: .collection, collection: entity
            ).clipSource == .collection(work.id)
        )
    }

    @Test("Lock Screen When Chosen configuration sets tap action on timeline entries and renders cleanly")
    func whenLockScreenActionConfigured_thenTimelineAndViewRender() throws {
        let full = try snapshot()
        let config = LockScreenClipsConfiguration(
            showsClipsOnLockScreen: true,
            tapAction: .openPesto,
            source: .recent
        )
        #expect(config.clipAction == .openPesto)
        #expect(LockScreenClipsConfiguration().clipAction == .copy)

        let actionTimeline = LockScreenClipsProvider.timeline(
            snapshot: full, now: now, showsClipsOnLockScreen: true, action: .openClip
        )
        #expect(actionTimeline.entries.allSatisfy { $0.action == .openClip })

        for action in LockScreenWidgetContent.Action.allCases {
            let entry = LockScreenClipsEntry(
                date: now, snapshot: full, showsClipsOnLockScreen: true, action: action
            )
            let view = LockScreenClipsView(entry: entry, familyOverride: .accessoryRectangular)
                .frame(width: 172, height: 72)
                .background(Color.black)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            _ = try #require(renderer.uiImage, "lockscreen-action-\(action.rawValue)")
        }
    }
}
