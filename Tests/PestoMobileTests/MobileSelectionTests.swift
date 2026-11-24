// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("Multi-select Copy All ordering and protection on iOS")
@MainActor
struct MobileSelectionTests {
    @Test("copyJoined joins textual clips in the given order and skips when locked")
    func whenCopyJoined_thenRespectsOrderAndLock() async throws {
        let library = try await MobileTestLibrary()
        let first = try await library.add("Alpha first")
        let second = try await library.add("Beta second")

        let ok = library.state.copyJoined([first, second])
        #expect(ok)
        #expect(library.state.notice?.text == "Copied")

        let lockedLibrary = try await MobileTestLibrary(
            lock: MobileHistoryLock(
                authenticator: StubUserAuthenticator(available: true, grants: true),
                grace: AuthenticationGrace(),
                isEnabled: { true }
            )
        )
        let lockedA = try await lockedLibrary.add("One")
        let lockedB = try await lockedLibrary.add("Two")
        lockedLibrary.state.lockHistory()
        #expect(!lockedLibrary.state.copyJoined([lockedA, lockedB]))
    }

    @Test("copyJoined ignores non-textual clips and needs at least two textual clips")
    func whenFewerThanTwoTextualClips_thenCopyJoinedReturnsFalse() async throws {
        let library = try await MobileTestLibrary()
        let text = try await library.add("Only one text")
        let link = try await library.add("https://copypesto.net")

        #expect(!library.state.copyJoined([text, link]))
    }

    @Test("copyJoined marks clipboard protected when any selected clip is sensitive and reports cap")
    func whenAnySensitiveOrOverCap_thenProtectedAndNoticed() throws {
        let now = Date.now
        let normal = ClipboardItem(
            timestamp: now, type: .text, previewText: "Plain", contentHash: "h1", byteSize: 5,
            deviceID: "d", sequenceNumber: 1
        )
        let secret = ClipboardItem(
            timestamp: now, type: .code, previewText: "token", sensitivity: .apiKey,
            contentHash: "h2", byteSize: 5, deviceID: "d", sequenceNumber: 2
        )
        let over = ClipboardItem(
            timestamp: now, type: .text, previewText: "Too big", contentHash: "h3",
            byteSize: ClipSizePolicy.maxTextBytes, deviceID: "d", sequenceNumber: 3
        )
        let joined = try #require(ClipJoin.join([normal, secret, over]))
        #expect(joined.text == "Plain\n\ntoken")
        #expect(joined.isProtected)
        #expect(joined.leftOut == 1)
    }
}
