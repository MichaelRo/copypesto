// SPDX-License-Identifier: MIT
import Foundation

/// On-device explicit-content detection for URL clipboard items.
///
/// Two-stage check: (1) static domain blocklist for known adult sites,
/// (2) keyword scoring on host + URL path components. All logic is local —
/// no network calls, no data leaves the device.
public enum NSFWURLDetector: Sendable {
    /// Lightweight value carrying link-preview fields used by the keyword scorer.
    /// Lets us union the page's title/description/site name into the corpus when
    /// the URL host is opaque (e.g., CDN domains, shorteners).
    public struct LinkPreviewSignals: Sendable {
        public let title: String?
        public let description: String?
        public let siteName: String?

        public init(title: String? = nil, description: String? = nil, siteName: String? = nil) {
            self.title = title
            self.description = description
            self.siteName = siteName
        }
    }

    /// Returns `true` if the URL appears to link to explicit content.
    public static func isExplicit(urlString: String, threshold: Float = 0.85) -> Bool {
        isExplicit(urlString: urlString, metadata: nil, threshold: threshold)
    }

    /// Metadata-aware variant: also scans `og:title`, `og:description`, `og:site_name`
    /// for keyword signals. Use this once link-preview metadata is fetched, so CDN/
    /// shortener URLs whose host is opaque can still be classified.
    public static func isExplicit(
        urlString: String,
        metadata: LinkPreviewSignals?,
        threshold: Float = 0.85
    )
    -> Bool {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased(),
              !host.isEmpty else { return false }

        if isBlocklisted(host: host) || hostContainsExplicitStem(host) { return true }

        var corpus = host + " " + url.path.lowercased()
        if let metadata {
            for piece in [metadata.title, metadata.description, metadata.siteName] {
                if let piece, !piece.isEmpty {
                    corpus += " " + piece.lowercased()
                }
            }
        }
        if corpus.contains("mature content") { return true }
        return keywordScore(in: corpus) >= threshold
    }

    // MARK: - Internal (package-internal for testability)

    static func isBlocklisted(host: String) -> Bool {
        let h = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return blocklist.contains { h == $0 || h.hasSuffix("." + $0) }
    }

    /// Hosts often run words together ("namethatpornad.com"), which whole-word scoring cannot see. These stems are
    /// long or distinctive enough not to occur inside innocent words; "sex" and "xxx" are left out on purpose
    /// ("essex", "xxxl").
    static func hostContainsExplicitStem(_ host: String) -> Bool {
        explicitHostStems.contains { host.contains($0) }
    }

    static func keywordScore(in text: String) -> Float {
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard !words.isEmpty else { return 0 }
        let strong = words.count(where: { strongKeywords.contains($0) })
        let weak = words.count(where: { weakKeywords.contains($0) })
        // One strong keyword alone clears 0.85; one weak keyword alone stays below.
        return min(Float(strong) * 0.9 + Float(weak) * 0.35, 1.0)
    }

    // MARK: - Static data

    private static let blocklist: Set<String> = [
        "pornhub.com", "xvideos.com", "xnxx.com", "redtube.com", "youporn.com",
        "tube8.com", "spankwire.com", "xtube.com", "porn.com", "sex.com",
        "brazzers.com", "bangbros.com", "naughtyamerica.com", "teamskeet.com",
        "digitalplayground.com", "penthouse.com", "hustler.com", "mofos.com",
        "realitykings.com", "babes.com", "elegantangel.com", "evilangel.com",
        "nhentai.net", "e-hentai.org", "rule34.xxx", "gelbooru.com",
        "onlyfans.com", "fansly.com", "manyvids.com", "clips4sale.com",
        "chaturbate.com", "cam4.com", "myfreecams.com", "livejasmin.com",
        "bongacams.com", "stripchat.com", "camsoda.com", "jerkmate.com",
        "motherless.com", "slutload.com", "drtuber.com", "beeg.com",
        "txxx.com", "vporn.com", "tnaflix.com", "fuq.com",
        "erome.com", "redgifs.com", "gfycat.com",
        "coomer.party", "coomer.su", "kemono.party", "kemono.su",
        "pornpics.com", "eporner.com", "spankbang.com",
        "xhamster.com", "xhamsterlive.com", "sxyprn.com",
        "hqporner.com", "hclips.com", "hotmovs.com", "tubegalore.com"
    ]

    private static let explicitHostStems = ["porn", "hentai", "xvideos", "xnxx", "xhamster", "nsfw"]

    private static let strongKeywords: Set<String> = [
        "porn", "porno", "xxx", "hentai", "nsfw",
        "cumshot", "creampie", "gangbang", "blowjob",
        "redgif", "erome", "nudes", "onlyfan", "camgirl", "sextape", "lewd"
    ]

    private static let weakKeywords: Set<String> = [
        "nude", "naked", "adult", "erotic", "fetish",
        "bdsm", "milf", "orgasm"
    ]
}
