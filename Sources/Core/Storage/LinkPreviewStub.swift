// SPDX-License-Identifier: MIT
import Foundation

/// What a benchmark's link preview answers with instead of a page: a title and a picture drawn in code, after a fixed
/// wait, so the shelf does the same work each run and no request leaves the Mac.
enum LinkPreviewStub {
    static func load(_ url: URL, delayMillis: Int) async throws -> URLPreviewResult {
        try await Task.sleep(for: .milliseconds(delayMillis))
        let seed = abs(url.absoluteString.hashValue % 10_000)
        return URLPreviewResult(
            title: "Stub page \(seed)",
            ogImageData: MixedSeed.pngData(seed: seed, width: 480, height: 260),
            faviconData: nil,
            siteName: "example.com"
        )
    }
}
