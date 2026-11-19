// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Testing
@testable import PestoCore
@testable import PestoCoreNetworking
@testable import PestoMobile

@Suite("A link card's preview is fetched once, under the switch, never while locked")
@MainActor
struct MobileLinkPreviewTests {
    private final class Calls {
        var urls: [URL] = []
    }

    private struct Fixture {
        let library: MobileTestLibrary
        let calls: Calls
        let images: LinkPreviewImageStore
        let folder: URL
    }

    private func fixture(enabled: Bool) async throws -> Fixture {
        let library = try await MobileTestLibrary()
        let calls = Calls()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-mobile-previews-\(UUID().uuidString)", isDirectory: true)
        let key = SymmetricKey(size: .bits256)
        let images = LinkPreviewImageStore(directory: folder, key: { key })
        let page = URLPreviewResult(
            title: "Basil, grown at home", ogImageData: Data([1, 2, 3]), faviconData: nil, siteName: "Basil Weekly"
        )
        library.state.linkPreviewLoader = LinkPreviewLoader(
            fetch: { url in
                calls.urls.append(url)
                return page
            },
            images: images, isEnabled: { enabled }, nsfwMode: { .show }
        )
        return Fixture(library: library, calls: calls, images: images, folder: folder)
    }

    @Test("with the switch on, the title, site and picture are stored once and the clip is marked fetched")
    func whenOn_thenFetchedAndStoredOnce() async throws {
        let fixture = try await fixture(enabled: true)
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let item = try await fixture.library.add("https://www.example.com/basil")

        let stored = await fixture.library.state.loadLinkPreview(for: item)
        let again = await fixture.library.state.loadLinkPreview(for: item)

        #expect(stored)
        #expect(!again)
        #expect(fixture.calls.urls.count == 1)
        #expect(item.ogTitle == "Basil, grown at home")
        #expect(item.ogSiteName == "Basil Weekly")
        #expect(item.linkPreviewFetched)
        #expect(fixture.images.load(for: item.id) == Data([1, 2, 3]))
    }

    @Test("with the switch off nothing is fetched and the clip stays unfetched")
    func whenOff_thenNoRequest() async throws {
        let fixture = try await fixture(enabled: false)
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let item = try await fixture.library.add("https://www.example.com/basil")

        #expect(await !fixture.library.state.loadLinkPreview(for: item))
        #expect(fixture.calls.urls.isEmpty)
        #expect(!item.linkPreviewFetched)
    }

    @Test("a locked history causes no request")
    func whenLocked_thenNoRequest() async throws {
        let library = try await MobileTestLibrary()
        let item = try await library.add("https://www.example.com/basil")

        #expect(LinkPreviewLoader.address(for: item, isEnabled: true, isHistoryLocked: true) == nil)
        #expect(LinkPreviewLoader.address(for: item, isEnabled: true, isHistoryLocked: false) != nil)
        #expect(LinkPreviewLoader.address(for: item, isEnabled: false, isHistoryLocked: false) == nil)
    }

    @Test("a private address is never fetched")
    func whenAddressIsLocal_thenNoRequest() async throws {
        let fixture = try await fixture(enabled: true)
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let item = try await fixture.library.add("http://192.168.1.10/router")

        #expect(await !fixture.library.state.loadLinkPreview(for: item))
        #expect(fixture.calls.urls.isEmpty)
    }

    @Test("a failed fetch is marked and not retried")
    func whenTheFetchFails_thenItIsMarkedAndNotRetried() async throws {
        let library = try await MobileTestLibrary()
        let calls = Calls()
        library.state.linkPreviewLoader = LinkPreviewLoader(
            fetch: { url in
                calls.urls.append(url)
                throw URLError(.notConnectedToInternet)
            },
            isEnabled: { true }, nsfwMode: { .show }
        )
        let item = try await library.add("https://www.example.com/offline")

        _ = await library.state.loadLinkPreview(for: item)
        _ = await library.state.loadLinkPreview(for: item)

        #expect(calls.urls.count == 1)
        #expect(item.linkPreviewFetched)
    }
}
