// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Shelf filters apply to search by meaning too")
struct ShelfFilterTests {
    private func clip(
        _ text: String, type: ClipboardType = .text, sensitive: Bool = false, bundle: String? = nil,
        collection: UUID? = nil, age: TimeInterval = 0
    )
    -> ClipboardItem {
        let item = ClipboardItem(
            timestamp: Date().addingTimeInterval(-age), type: type, sourceBundleID: bundle, previewText: text,
            contentHash: UUID().uuidString, byteSize: text.utf8.count, deviceID: "d", sequenceNumber: 1,
            collectionID: collection
        )
        item.isNSFW = sensitive
        return item
    }

    private func filter(
        hidesSensitive: Bool = false, bundle: String? = nil, collection: UUID? = nil,
        searchActive: Bool = false, types: Set<String> = [], sources: Set<String> = [],
        date: SearchDateFilter = .all, sensitiveOnly: Bool = false, remoteOnly: Bool = false
    )
    -> ShelfFilter {
        ShelfFilter(
            hidesSensitive: hidesSensitive, appBundleIDs: bundle.map { [$0] } ?? [],
            inCollection: collection.map { id in { $0.collectionID == id } },
            searchActive: searchActive, types: types, sources: sources, date: date, sensitiveOnly: sensitiveOnly,
            remoteOnly: remoteOnly
        )
    }

    @Test("a sensitive clip the shelf hides is not brought back by a search by meaning")
    func hiddenClipStaysHidden() {
        let hidden = clip("holiday photos from the beach", sensitive: true)
        let shown = clip("holiday plans")

        let result = filter(hidesSensitive: true).apply(to: [hidden, shown])

        #expect(result.map(\.id) == [shown.id])
    }

    @Test("inside a collection only that collection's clips are offered")
    func collectionScopes() {
        let board = UUID()
        let inside = clip("a", collection: board)
        let outside = clip("b")

        #expect(filter(collection: board).apply(to: [inside, outside]).map(\.id) == [inside.id])
    }

    @Test("several app chips keep the clips of any of them")
    func appChipsAreAnyOf() {
        let notes = clip("a", bundle: "com.apple.Notes")
        let mail = clip("b", bundle: "com.apple.mail")
        let safari = clip("c", bundle: "com.apple.Safari")
        let filter = ShelfFilter(
            hidesSensitive: false, appBundleIDs: ["com.apple.Notes", "com.apple.mail"], inCollection: nil,
            searchActive: false, types: [], sources: [], date: .all, sensitiveOnly: false
        )

        #expect(filter.apply(to: [notes, mail, safari]).map(\.id) == [notes.id, mail.id])
    }

    @Test("the app chips keep only clips from the chosen apps")
    func appContext() {
        let notes = clip("a", bundle: "com.apple.Notes")
        let mail = clip("b", bundle: "com.apple.mail")

        #expect(filter(bundle: "com.apple.Notes").apply(to: [notes, mail]).map(\.id) == [notes.id])
    }

    @Test("shelf app chips and search source chips combine as any-of while a search is active")
    func whenAppChipAndSearchSourceDiffer_thenKeepsClipsFromEither() {
        let notes = clip("a", bundle: "com.apple.Notes")
        let mail = clip("b", bundle: "com.apple.mail")
        let safari = clip("c", bundle: "com.apple.Safari")
        let filter = ShelfFilter(
            hidesSensitive: false, appBundleIDs: ["com.apple.Notes"], inCollection: nil,
            searchActive: true, types: [], sources: ["com.apple.mail"], date: .all, sensitiveOnly: false
        )

        #expect(filter.apply(to: [notes, mail, safari]).map(\.id) == [notes.id, mail.id])
    }

    @Test("the type, source and date chips narrow the results while a search is active")
    func searchBarChips() {
        let recentImage = clip("img", type: .image, bundle: "a", age: 60)
        let oldImage = clip("old", type: .image, bundle: "a", age: 40 * 86_400)
        let recentText = clip("txt", type: .text, bundle: "b", age: 60)
        let all = [recentImage, oldImage, recentText]

        #expect(filter(searchActive: true, types: ["image"]).apply(to: all).map(\.id) == [recentImage.id, oldImage.id])
        #expect(filter(searchActive: true, sources: ["b"]).apply(to: all).map(\.id) == [recentText.id])
        #expect(filter(searchActive: true, date: .week).apply(to: all).map(\.id) == [recentImage.id, recentText.id])

        let startOfToday = Calendar.current.startOfDay(for: Date())
        let fromToday = clip("today", age: -startOfToday.addingTimeInterval(60).timeIntervalSinceNow)
        let fromYesterday = clip("yesterday", age: -startOfToday.addingTimeInterval(-3600).timeIntervalSinceNow)
        let fromTwoDaysAgo = clip(
            "two days ago",
            age: -startOfToday.addingTimeInterval(-30 * 3600).timeIntervalSinceNow
        )
        #expect(
            filter(searchActive: true, date: .yesterday)
                .apply(to: [fromToday, fromYesterday, fromTwoDaysAgo])
                .map(\.id) == [fromYesterday.id]
        )
    }

    @Test("the chips do nothing while no search is active")
    func chipsNeedASearch() {
        let item = clip("a", type: .text)

        #expect(filter(searchActive: false, types: ["image"]).apply(to: [item]).count == 1)
    }

    @Test("Sensitive-only keeps only the clips marked sensitive")
    func sensitiveOnly() {
        let marked = clip("a", sensitive: true)
        let plain = clip("b")

        #expect(filter(searchActive: true, sensitiveOnly: true).apply(to: [marked, plain]).map(\.id) == [marked.id])
    }

    @Test("Sensitive-only also finds a detected secret, which a search by words cannot reach")
    func sensitiveOnly_includesDetectedSecrets() {
        let secret = clip("4111 1111 1111 1111")
        secret.sensitivityRaw = SensitivityCategory.creditCard.rawValue
        let plain = clip("b")

        #expect(filter(searchActive: true, sensitiveOnly: true).apply(to: [secret, plain]).map(\.id) == [secret.id])
    }

    @Test("Other Devices keeps only the clips that arrived from another device")
    func remoteOnly() {
        let fromPhone = clip("a")
        fromPhone.isRemote = true
        let local = clip("b")

        #expect(filter(searchActive: true, remoteOnly: true).apply(to: [fromPhone, local]).map(\.id) == [fromPhone.id])
        #expect(filter(searchActive: false, remoteOnly: true).apply(to: [fromPhone, local]).count == 2)
    }

    @Test("the text-match step sits between scope and the chips, and the supplement is filtered like the rest")
    func supplementIsFilteredLikeTheRest() {
        let hidden = clip("beach", sensitive: true)
        let textHit = clip("beach day")
        let meaningHit = clip("seaside trip")
        let filter = filter(hidesSensitive: true)

        let result = filter.search(
            in: [hidden, textHit, meaningHit],
            textMatches: { $0.filter { $0.id == textHit.id } },
            supplement: [hidden, meaningHit, textHit]
        )

        #expect(result.map(\.id) == [textHit.id, meaningHit.id])
    }
}
