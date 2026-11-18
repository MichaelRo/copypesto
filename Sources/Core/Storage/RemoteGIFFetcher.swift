// SPDX-License-Identifier: MIT
import Foundation

/// The fetch behind a browser's Copy Image, which hands over a still picture and names the GIF's address: it follows
/// the Link Previews switch and the address checks of a preview, and a locked history causes no request (ADR 0005).
public enum RemoteGIFFetcher {
    public static func make(
        isHistoryLocked: @escaping @Sendable () async -> Bool,
        isEnabled: @escaping @Sendable () -> Bool = { LinkPreviewPolicy.isEnabled() },
        download: @escaping @Sendable (URL) async -> Data? = { await URLMetadataFetcher.downloadPicture(from: $0) }
    )
    -> @Sendable (URL) async -> Data? {
        { address in
            let locked = await isHistoryLocked()
            guard LinkPreviewPolicy.mayFetchGIF(
                isEnabled: isEnabled(), isEligible: LinkPreviewEligibility.isEligible(address),
                isHistoryLocked: locked
            ) else { return nil }
            return await download(address)
        }
    }
}
