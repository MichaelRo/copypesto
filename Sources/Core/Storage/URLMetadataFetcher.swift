// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import ImageIO
import LinkPresentation
import UniformTypeIdentifiers

public struct URLPreviewResult: Sendable {
    public let title: String?
    public let ogImageData: Data?
    public let faviconData: Data?
    public let siteName: String?

    public init(title: String?, ogImageData: Data?, faviconData: Data?, siteName: String?) {
        self.title = title
        self.ogImageData = ogImageData
        self.faviconData = faviconData
        self.siteName = siteName
    }
}

@MainActor
public final class URLMetadataFetcher {
    public static let shared = URLMetadataFetcher()
    /// Upper bound for animated GIFs stored on the model. Larger payloads fall
    /// back to a static JPEG thumbnail to keep memory + SwiftData blobs sane.
    public nonisolated static let maxAnimatedGIFBytes = 8 * 1024 * 1024
    /// At most this many pages are fetched at once, and this many results are kept: flicking past hundreds of link
    /// cards
    /// must not contact every host together, and a session must not hold every picture it ever saw.
    public nonisolated static let maxConcurrentFetches = 3
    public nonisolated static let maxCachedPreviews = 100

    private var cache: [URL: URLPreviewResult] = [:]
    private var cacheOrder: [URL] = []
    private var inFlight: [URL: Task<URLPreviewResult, any Error>] = [:]
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private let isEnabled: @MainActor () -> Bool
    private let linkPreviewCache: LinkPreviewCache?
    private let loader: @Sendable (URL) async throws -> URLPreviewResult

    public init(
        isEnabled: @escaping @MainActor () -> Bool = { LinkPreviewPolicy.isEnabled() },
        linkPreviewCache: LinkPreviewCache? = LinkPreviewCache.shared,
        loader: @escaping @Sendable (URL) async throws -> URLPreviewResult = {
            try await URLMetadataFetcher.loadFromNetwork(url: $0)
        }
    ) {
        self.isEnabled = isEnabled
        self.linkPreviewCache = linkPreviewCache
        self.loader = loader
    }

    public func fetch(url: URL) async throws -> URLPreviewResult {
        // This is the one place that goes to the network, so it checks the person's switch itself.
        guard isEnabled() else { throw URLError(.dataNotAllowed) }
        guard let unwrapped = LinkPreviewEligibility.fetchTarget(for: url) else { throw URLError(.unsupportedURL) }

        if let synth = SearchEnginePreviewSynthesizer.synthesize(unwrapped) {
            let result = URLPreviewResult(
                title: synth.title,
                ogImageData: nil,
                faviconData: nil,
                siteName: synth.siteName
            )
            remember(result, for: url)
            if unwrapped != url { remember(result, for: unwrapped) }
            return result
        }

        if let cached = cache[url] ?? cache[unwrapped] { return cached }

        if let entry = linkPreviewCache?.entry(for: unwrapped) {
            if entry.isNegative {
                let empty = URLPreviewResult(title: nil, ogImageData: nil, faviconData: nil, siteName: nil)
                remember(empty, for: url)
                return empty
            }
            let result = URLPreviewResult(
                title: entry.title,
                ogImageData: entry.ogImageData,
                faviconData: entry.faviconData,
                siteName: entry.siteName
            )
            remember(result, for: url)
            if unwrapped != url { remember(result, for: unwrapped) }
            return result
        }

        // The same link asked for twice at once (a card scrolled off and back) is one request.
        if let pending = inFlight[url] ?? inFlight[unwrapped] { return try await pending.value }
        let task = Task { try await fetchLimited(url: unwrapped, originalURL: url) }
        inFlight[url] = task
        if unwrapped != url { inFlight[unwrapped] = task }
        defer {
            inFlight[url] = nil
            if unwrapped != url { inFlight[unwrapped] = nil }
        }
        return try await task.value
    }

    private func fetchLimited(url: URL, originalURL: URL) async throws -> URLPreviewResult {
        await acquireSlot()
        defer { releaseSlot() }
        let result: URLPreviewResult
        do {
            result = try await loader(url)
            let withGIF = await addingDirectGIF(to: result, for: url)
            remember(withGIF, for: originalURL)
            if url != originalURL { remember(withGIF, for: url) }
            let entry = LinkPreviewCache.Entry(
                title: withGIF.title,
                siteName: withGIF.siteName,
                faviconData: withGIF.faviconData,
                ogImageData: withGIF.ogImageData,
                isNegative: false
            )
            linkPreviewCache?.store(entry, for: url)
            if url != originalURL { linkPreviewCache?.store(entry, for: originalURL) }
            return withGIF
        } catch where Self.isDirectGIFLink(url) {
            // Link previews often fail for a bare image URL; the picture is still worth showing.
            result = URLPreviewResult(title: nil, ogImageData: nil, faviconData: nil, siteName: nil)
            let withGIF = await addingDirectGIF(to: result, for: url)
            remember(withGIF, for: originalURL)
            if url != originalURL { remember(withGIF, for: url) }
            if withGIF.ogImageData != nil {
                let entry = LinkPreviewCache.Entry(
                    title: nil,
                    siteName: nil,
                    faviconData: nil,
                    ogImageData: withGIF.ogImageData,
                    isNegative: false
                )
                linkPreviewCache?.store(entry, for: url)
                if url != originalURL { linkPreviewCache?.store(entry, for: originalURL) }
            }
            return withGIF
        } catch {
            let negativeEntry = LinkPreviewCache.Entry(
                title: nil,
                siteName: nil,
                faviconData: nil,
                ogImageData: nil,
                isNegative: true
            )
            linkPreviewCache?.store(negativeEntry, for: url)
            if url != originalURL { linkPreviewCache?.store(negativeEntry, for: originalURL) }
            throw error
        }
    }

    private func remember(_ result: URLPreviewResult, for url: URL) {
        if cache[url] == nil { cacheOrder.append(url) }
        cache[url] = result
        while cacheOrder.count > Self.maxCachedPreviews {
            cache[cacheOrder.removeFirst()] = nil
        }
    }

    private func acquireSlot() async {
        if running < Self.maxConcurrentFetches {
            running += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func releaseSlot() {
        if waiting.isEmpty {
            running -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }

    /// LinkPresentation returns no picture for a link straight to a GIF, and re-encodes page pictures as still images.
    private func addingDirectGIF(to result: URLPreviewResult, for url: URL) async -> URLPreviewResult {
        guard result.ogImageData == nil, Self.isDirectGIFLink(url),
              let gif = await Self.downloadGIF(from: url),
              let card = Self.processOGImageData(gif) else { return result }
        return URLPreviewResult(
            title: result.title, ogImageData: card, faviconData: result.faviconData, siteName: result.siteName
        )
    }

    public nonisolated static let maxDownloadBytes = 16 * 1024 * 1024

    public nonisolated static func isDirectGIFLink(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.pathExtension.lowercased() == "gif"
    }

    /// The GIF at `url`, or nil for an error status, a body that is not a GIF, or one over `maxDownloadBytes`.
    public nonisolated static func downloadGIF(from url: URL, session: URLSession = .shared) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("image/gif,image/*;q=0.8", forHTTPHeaderField: "Accept")
        let download = BoundedDownload(limit: maxDownloadBytes)
        let owned = URLSession(configuration: session.configuration, delegate: download, delegateQueue: nil)
        defer { owned.finishTasksAndInvalidate() }
        let data = await download.run(owned.dataTask(with: request))
        return data?.isGIF == true ? data : nil
    }

    /// nonisolated so LPLinkMetadata (non-Sendable in macOS 15 SDK) never crosses an
    /// isolation boundary — it is created and consumed entirely within this function.
    public nonisolated static func loadFromNetwork(url: URL) async throws -> URLPreviewResult {
        let provider = LPMetadataProvider()
        provider.shouldFetchSubresources = true
        provider.timeout = 15

        let meta = try await provider.startFetchingMetadata(for: url)

        let title = meta.title
        let siteName = meta.value(forKey: "siteName") as? String

        // NSItemProvider is not Sendable in macOS 15 SDK. Box it in @unchecked Sendable
        // for withCheckedContinuation; safe because we never hop threads here.
        struct Box: @unchecked Sendable { let value: NSItemProvider }

        var ogImageData: Data?
        if let imageProvider = meta.imageProvider {
            let box = Box(value: imageProvider)
            let raw = await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
                box.value.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    cont.resume(returning: data)
                }
            }
            ogImageData = raw.flatMap { URLMetadataFetcher.processOGImageData($0) }
        }

        var faviconData: Data?
        if let iconProvider = meta.iconProvider {
            let box = Box(value: iconProvider)
            faviconData = await withCheckedContinuation { cont in
                box.value.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, _ in
                    cont.resume(returning: data)
                }
            }
        }

        var finalOGImageData = ogImageData
        if finalOGImageData == nil {
            finalOGImageData = await scrapeOGImage(from: url)
        }

        return URLPreviewResult(
            title: title,
            ogImageData: finalOGImageData,
            faviconData: faviconData,
            siteName: siteName
        )
    }

    /// Extracts an image URL from HTML `<meta>` tags (og:image, og:image:secure_url, twitter:image).
    /// Pure function — exposed for unit testing.
    public nonisolated static func extractOGImageURL(from html: String) -> URL? {
        let patterns = [
            #"<meta\s+[^>]*property=["']og:image(?::secure_url)?["'][^>]*content=["']([^"']+)["']"#,
            #"<meta\s+[^>]*content=["']([^"']+)["'][^>]*property=["']og:image(?::secure_url)?["']"#,
            #"<meta\s+[^>]*name=["']twitter:image(?::src)?["'][^>]*content=["']([^"']+)["']"#,
            #"<meta\s+[^>]*content=["']([^"']+)["'][^>]*name=["']twitter:image(?::src)?["']"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            if let match = regex.firstMatch(in: html, range: range),
               let matchRange = Range(match.range(at: 1), in: html)
            {
                let urlString = String(html[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if let url = URL(string: urlString), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    return url
                }
            }
        }
        return nil
    }

    /// Fetches the head of the page HTML at `url` and attempts to scrape the OpenGraph / Twitter preview image.
    public nonisolated static func scrapeOGImage(from url: URL, session: URLSession = .shared) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        // Limit HTML download to 64 KB so large pages are never read entirely
        let download = BoundedDownload(limit: 64 * 1024)
        let owned = URLSession(configuration: session.configuration, delegate: download, delegateQueue: nil)
        defer { owned.finishTasksAndInvalidate() }
        guard let data = await download.run(owned.dataTask(with: request)),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii),
              let imageURL = extractOGImageURL(from: html) else
        {
            return nil
        }

        // The address came out of a page we do not control: it is vetted like the page's own (R-03, S-19).
        guard LinkPreviewEligibility.isEligible(imageURL) else { return nil }
        var imgRequest = URLRequest(url: imageURL, timeoutInterval: 10)
        imgRequest.setValue("image/*;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let imgDownload = BoundedDownload(limit: maxDownloadBytes)
        let imgOwned = URLSession(configuration: session.configuration, delegate: imgDownload, delegateQueue: nil)
        defer { imgOwned.finishTasksAndInvalidate() }
        guard let imgData = await imgDownload.run(imgOwned.dataTask(with: imgRequest)) else {
            return nil
        }
        return processOGImageData(imgData)
    }

    /// Decides how raw og:image bytes should be persisted: an animated picture stays animated (as a GIF), anything else
    /// is re-encoded by `thumbnail()`.
    /// Pure function — exposed for unit testing.
    public nonisolated static func processOGImageData(_ raw: Data) -> Data? {
        // Scaled and frame-capped, so a card never has to decode a huge animation. A GIF already smaller than its
        // copy is kept as it came; a WebP or PNG animation (what GIPHY sends) is always turned into a GIF.
        if let small = ImageDownsampler.animatedGIF(from: raw, maxPixel: 600, maxFrames: 60),
           !raw.isGIF || small.count <= raw.count
        {
            return small
        }
        if raw.isGIF, raw.count <= maxAnimatedGIFBytes { return raw }
        return URLMetadataFetcher.thumbnail(from: raw, maxBytes: 49_152)
    }

    /// Scales the image down with ImageIO (thread-safe) and compresses as JPEG. Returns nil
    /// if the image can't be decoded or compressed below `maxBytes` at minimum quality.
    public nonisolated static func thumbnail(from data: Data, maxBytes: Int) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }

        let thumbOptions = [
            kCGImageSourceThumbnailMaxPixelSize: 600,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else { return nil }

        for quality in [0.75, 0.55, 0.35] as [Double] {
            let dest = NSMutableData()
            guard let sink = CGImageDestinationCreateWithData(
                dest as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
            ) else { continue }
            CGImageDestinationAddImage(
                sink, cgImage,
                [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
            )
            guard CGImageDestinationFinalize(sink) else { continue }
            if dest.length <= maxBytes { return dest as Data }
        }
        return nil
    }
}
