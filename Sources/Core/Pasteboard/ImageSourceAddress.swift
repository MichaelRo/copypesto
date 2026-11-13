// SPDX-License-Identifier: MIT
import Foundation

/// Where a copied picture came from, when it came from a GIF on a web page. A browser's Copy Image puts the first frame
/// on the pasteboard as a still picture, with the picture's address in an `<img>` tag of the HTML flavour; Pesto can
/// fetch the GIF itself from there (ADR 0005), under the same switch and the same checks as a link preview.
public enum ImageSourceAddress {
    /// Only the start of the HTML is read: the tag a browser writes for Copy Image is the whole of it.
    private static let readLimit = 100_000

    private static let imageTag = try? NSRegularExpression(
        pattern: #"<img\b[^>]*?\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)')"#, options: [.caseInsensitive]
    )

    /// Sites such as GIPHY and Tenor send a browser the animation as WebP, so a Copy Image names `.webp` as often as
    /// `.gif`; both can hold the whole animation, and a still one is refused when it arrives.
    public static func animatedPictureURL(inHTML html: String) -> URL? {
        imageURLs(inHTML: html).first(where: { ["gif", "webp"].contains($0.pathExtension.lowercased()) })
    }

    public static func imageURL(inHTML html: String) -> URL? {
        imageURLs(inHTML: html).first
    }

    private static func decodeHTMLEntities(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func imageURLs(inHTML html: String) -> [URL] {
        guard let imageTag else { return [] }
        let head = String(html.prefix(readLimit))
        let range = NSRange(head.startIndex..., in: head)
        var urls: [URL] = []
        for match in imageTag.matches(in: head, range: range) {
            let rawAddress = [1, 2].lazy.compactMap { index -> String? in
                Range(match.range(at: index), in: head).map { String(head[$0]) }
            }.first
            guard let rawAddress else { continue }
            let address = decodeHTMLEntities(rawAddress)
            guard let url = URL(string: address), url.scheme?.lowercased() == "https",
                  LinkPreviewEligibility.isEligible(url) else { continue }
            urls.append(url)
        }
        return urls
    }
}
