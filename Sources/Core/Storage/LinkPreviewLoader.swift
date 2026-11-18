// SPDX-License-Identifier: MIT
import Foundation
import os

/// Fetches a link clip's page title, site name and picture once and stores them, for an app with no card view to do it
/// (the iPhone and iPad library; the Mac's card does the same steps in `ClipboardCard+Loading`). The Link Previews
/// switch, the address checks and a locked history are decided here (ADR 0005); a clip is fetched once, whatever the
/// result.
@MainActor
public struct LinkPreviewLoader {
    public typealias Fetch = @MainActor (URL) async throws -> URLPreviewResult

    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "LinkPreviewLoader")

    private let fetch: Fetch
    private let images: LinkPreviewImageStore
    private let isEnabled: @MainActor () -> Bool
    private let nsfwMode: @MainActor () -> NSFWMode
    private let screener: any ImageSensitivityScreening

    public init(
        fetch: @escaping Fetch = { try await URLMetadataFetcher.shared.fetch(url: $0) },
        images: LinkPreviewImageStore = LinkPreviewImageStore(),
        isEnabled: @escaping @MainActor () -> Bool = { LinkPreviewPolicy.isEnabled() },
        nsfwMode: @escaping @MainActor () -> NSFWMode = { NSFWMode.current() },
        screener: any ImageSensitivityScreening = OnDeviceImageScreener()
    ) {
        self.fetch = fetch
        self.images = images
        self.isEnabled = isEnabled
        self.nsfwMode = nsfwMode
        self.screener = screener
    }

    /// The address to fetch for this clip now, or nil: not a link, the switch off, the history locked, a secret, an
    /// address that is not a public web page, or one already fetched.
    public static func address(for item: ClipboardItem, isEnabled: Bool, isHistoryLocked: Bool) -> URL? {
        guard item.type == .url, isEnabled, !isHistoryLocked, item.sensitivityRaw == nil,
              !item.linkPreviewFetched, !item.analysisPending,
              let link = URL(string: item.displayPreviewText),
              LinkPreviewEligibility.isEligible(link) else { return nil }
        return link
    }

    /// Fetches and stores the preview. Returns whether a picture was stored, so a card can load it.
    @discardableResult
    public func load(_ item: ClipboardItem, isHistoryLocked: Bool, editor: ClipEditor) async -> Bool {
        guard let link = Self.address(for: item, isEnabled: isEnabled(), isHistoryLocked: isHistoryLocked) else {
            return false
        }
        let id = item.id
        let result = try? await fetch(link)
        guard !Task.isCancelled, !item.isDeleted, item.type == .url else { return false }
        var explicit = false
        let mode = nsfwMode()
        if let result, mode.detectsContent, !item.isNSFW {
            explicit = NSFWURLDetector.isExplicit(
                urlString: item.displayPreviewText,
                metadata: .init(title: result.title, description: nil, siteName: result.siteName)
            )
            if !explicit, let data = result.ogImageData { explicit = await screener.isSensitive(imageData: data) }
        }
        var storedPicture = false
        if let data = result?.ogImageData {
            do {
                try images.save(data, for: id)
                storedPicture = true
            } catch {
                Self.logger
                    .error("A link preview picture was not saved: \(error.localizedDescription, privacy: .public)")
            }
        }
        editor.applyDerived(to: item, changesFilter: explicit, reportsFailure: explicit) {
            if let result {
                if $0.ogTitle != result.title { $0.ogTitle = result.title }
                if $0.ogSiteName != result.siteName { $0.ogSiteName = result.siteName }
            }
            $0.linkPreviewFetched = true
            if explicit { $0.isNSFW = true }
        }
        return storedPicture
    }
}
