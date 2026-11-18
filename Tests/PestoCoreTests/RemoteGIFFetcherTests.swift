// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The fetch behind a browser's Copy Image follows the Link Previews switch")
struct RemoteGIFFetcherTests {
    private actor Counter {
        private(set) var value = 0

        func bump() {
            value += 1
        }
    }

    private func fetch(
        _ address: String, enabled: Bool, locked: Bool, counter: Counter
    ) async throws
    -> Data? {
        let fetcher = RemoteGIFFetcher.make(
            isHistoryLocked: { locked }, isEnabled: { enabled },
            download: { _ in
                await counter.bump()
                return Data("GIF89a".utf8)
            }
        )
        return try await fetcher(#require(URL(string: address)))
    }

    @Test("on, unlocked and a public address: the picture is downloaded")
    func whenAllowed_thenDownloaded() async throws {
        let counter = Counter()
        #expect(try await fetch("https://media.example.com/a.gif", enabled: true, locked: false, counter: counter) !=
            nil)
        #expect(await counter.value == 1)
    }

    @Test("switched off, locked or a private address: no request at all")
    func whenNotAllowed_thenNoRequest() async throws {
        let counter = Counter()
        #expect(try await fetch("https://media.example.com/a.gif", enabled: false, locked: false, counter: counter) ==
            nil)
        #expect(try await fetch("https://media.example.com/a.gif", enabled: true, locked: true, counter: counter) ==
            nil)
        #expect(try await fetch("http://192.168.1.2/a.gif", enabled: true, locked: false, counter: counter) == nil)
        #expect(await counter.value == 0)
    }
}
