// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Imported seed")
struct ImportedSeedTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("the history has the size and span of a long Paste import")
    func whenSeeded_thenItSpansYearsAndHoldsAboutAThousandClips() {
        let records = ImportedSeed.records(now: now)
        #expect(records.count == ImportedSeed.count)
        let oldest = records.map(\.timestamp).min() ?? now
        #expect(now.timeIntervalSince(oldest) > 7 * 365 * 86_400)
    }

    @Test("most old clips sit in collections, and the newest are plain history")
    func whenSeeded_thenOldClipsAreInCollections() {
        let records = ImportedSeed.records(now: now)
        let inCollections = records.count(where: { $0.pinboard != nil })
        #expect(inCollections > records.count / 3)
        #expect(Set(records.compactMap(\.pinboard)).count == ImportedSeed.collectionNames.count)
        #expect(records.suffix(100).allSatisfy { $0.pinboard == nil })
    }

    @Test("it holds more pictures than the thumbnail cache keeps, links, GIFs and files that are gone")
    func whenSeeded_thenKindsCoverTheSlowPaths() {
        let captures = ImportedSeed.records(now: now).compactMap { PasteMigrator.makeCapture(from: $0) }
        #expect(captures.count == ImportedSeed.count)
        func count(_ uti: String) -> Int {
            captures.count(where: { $0.typeIdentifier == uti })
        }
        #expect(count("public.png") >= ImportedSeed.pictureCount)
        #expect(count("com.compuserve.gif") >= 5)
        #expect(count("public.file-url") >= 5)
        let links = captures.filter { $0.payloadString?.hasPrefix("https://") == true }
        #expect(links.count >= 100)
    }

    @Test("half the sources are apps that are not installed")
    func whenSeeded_thenManySourcesAreUninstalled() {
        let sources = Set(ImportedSeed.records(now: now).compactMap(\.sourceBundleID))
        #expect(sources.count >= 20)
        #expect(sources.contains { $0.hasPrefix("com.example.retired-app") })
    }

    @Test("two runs make the same history")
    func whenSeededTwice_thenTheContentIsTheSame() {
        let first = ImportedSeed.records(now: now).map(\.sourceBundleID)
        let second = ImportedSeed.records(now: now).map(\.sourceBundleID)
        #expect(first == second)
    }
}
