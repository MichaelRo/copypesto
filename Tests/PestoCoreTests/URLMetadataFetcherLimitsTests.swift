// SPDX-License-Identifier: MIT
import Foundation
import Synchronization
import Testing
@testable import PestoCore

private final class FetchCounter: Sendable {
    private let state = Mutex((running: 0, mostAtOnce: 0, started: 0))

    func begin() {
        state.withLock { counts in
            counts.running += 1
            counts.started += 1
            counts.mostAtOnce = max(counts.mostAtOnce, counts.running)
        }
    }

    func end() {
        state.withLock { $0.running -= 1 }
    }

    var mostAtOnce: Int {
        state.withLock { $0.mostAtOnce }
    }

    var started: Int {
        state.withLock { $0.started }
    }
}

@Suite("Link preview fetching is limited")
@MainActor
struct URLMetadataFetcherLimitsTests {
    private func fetcher(counter: FetchCounter) -> URLMetadataFetcher {
        URLMetadataFetcher(isEnabled: { true }, loader: { _ in
            counter.begin()
            try? await Task.sleep(for: .milliseconds(80))
            counter.end()
            return URLPreviewResult(title: "page", ogImageData: nil, faviconData: nil, siteName: nil)
        })
    }

    @Test("many links asked for at once are fetched only a few at a time")
    func whenManyLinksAreAskedForTogether_thenOnlyAFewAreInFlight() async throws {
        let counter = FetchCounter()
        let fetcher = fetcher(counter: counter)
        // Addresses no other test uses: the fetcher consults the process-wide link cache, so a shared address could be
        // answered from it and never started.
        let run = UUID().uuidString
        let urls = try (0..<12).map { try #require(URL(string: "https://example.com/\(run)/page/\($0)")) }

        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask { _ = try? await fetcher.fetch(url: url) }
            }
        }

        #expect(counter.started == 12)
        #expect(counter.mostAtOnce <= URLMetadataFetcher.maxConcurrentFetches, "\(counter.mostAtOnce) at once")
    }

    @Test("the same link asked for several times at once is one request")
    func whenTheSameLinkIsAskedForRepeatedly_thenItIsFetchedOnce() async throws {
        let counter = FetchCounter()
        let fetcher = fetcher(counter: counter)
        let url = try #require(URL(string: "https://example.com/\(UUID().uuidString)/recipes"))

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask { _ = try? await fetcher.fetch(url: url) }
            }
        }
        _ = try await fetcher.fetch(url: url)

        #expect(counter.started == 1)
    }
}
