// SPDX-License-Identifier: MIT
import Foundation
import Testing

// Enforces AGENTS.md security invariant 1: no third-party endpoints. Pesto sends no clip content to any AI service;
// see decisions/0005-no-network-but-a-short-list-and-ai-on-the-device.md.

@Suite("NetworkGuard")
struct NetworkGuardTests {
    /// Hosts the app may name in a string literal. Anything else needs an ADR and an entry here.
    private static let allowedLiteralHosts: Set<String> = [
        "maps.apple.com", // "Open in Maps" for a detected address: opened by the user, not fetched by Pesto
        // "Track with ..." for a detected tracking number: the carrier's page is opened in the user's browser
        "www.ups.com", "tools.usps.com", "www.fedex.com", "www.dhl.com",
        "copypesto.net" // Sparkle appcast (user-controlled updates); see Info.plist SUFeedURL
    ]

    /// The only files that may open a connection themselves. A new network-capable file needs an edit here and a
    /// reason.
    private static let networkCallSites: Set<String> = [
        "Sources/Core/Storage/URLMetadataFetcher.swift", // link previews: switchable off, checked inside `fetch`
        "Sources/Core/Storage/BoundedDownload.swift" // reads the GIF body for `URLMetadataFetcher`; starts nothing
    ]

    /// Sample clipboard text for UI tests, not endpoints.
    private static let seedFiles: Set<String> = [
        "Sources/Core/Seeding/SeedFixtures.swift", "Sources/Core/Seeding/MarketingSeed.swift",
        "Sources/Core/Seeding/MixedSeed.swift", "Sources/Core/Seeding/LatencySeed.swift",
        "Sources/Core/Seeding/LunchRushSeed.swift",
        "Sources/Features/Grid/SampleCardStrip.swift" // the sample cards on the ready screen and in Appearance
    ]

    private static let scannedExtensions: Set<String> = ["swift", "plist", "sdef", "xcstrings", "json"]

    private static func scannedFiles() throws -> [URL] {
        try SourceTree.files(in: "", extensions: scannedExtensions, minimum: 280)
    }

    private static func codeLines(_ file: URL) throws -> [(number: Int, line: String)] {
        try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n").enumerated()
            .filter { !$0.element.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .map { ($0.offset + 1, $0.element) }
    }

    @Test("every URL literal in the app points at an allowed host")
    func everyURLLiteral_isOnTheAllowlist() throws {
        let pattern = try NSRegularExpression(pattern: #""(?:https?|wss?|ftps?)://([A-Za-z0-9.\-]+)"#)
        var offenders: [String] = []
        for file in try Self.scannedFiles() where !Self.seedFiles.contains(SourceTree.relativePath(file)) {
            for (number, line) in try Self.codeLines(file) where !line.contains("DOCTYPE") {
                for match in pattern.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                    guard let hostRange = Range(match.range(at: 1), in: line) else { continue }
                    let host = String(line[hostRange])
                    if !Self.allowedLiteralHosts.contains(host) {
                        offenders.append("\(SourceTree.relativePath(file)):\(number): \(host)")
                    }
                }
            }
        }
        #expect(offenders.isEmpty, "URL literals outside the allowlist: \(offenders)")
    }

    @Test("no URL is assembled at run time from a host the guard cannot see")
    func noConstructedURLs() throws {
        let patterns = try [
            #""(?:https?|wss?|ftps?|sftp)://\\\("#, // "https://\(host)/path"
            #""(?:https?|wss?|ftps?)://"\s*\+"#, // "https://" + host
            #"\.scheme\s*=\s*"(?:https?|wss?|ftps?)""# // URLComponents built piece by piece
        ].map { try NSRegularExpression(pattern: $0) }
        var offenders: [String] = []
        for file in try Self.scannedFiles() where !Self.seedFiles.contains(SourceTree.relativePath(file)) {
            for (number, line) in try Self.codeLines(file)
                where patterns
                .contains(where: { $0.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil })
            {
                offenders.append("\(SourceTree.relativePath(file)):\(number)")
            }
        }
        #expect(offenders.isEmpty, "a URL is built from parts: \(offenders)")
    }

    @Test("only the listed files open a network connection")
    func networkCallSitesAreConfined() throws {
        let apis = [
            "URLSession", "URLRequest", "NWConnection", "NWBrowser", "NWPathMonitor", "NetService",
            "LPMetadataProvider", "WKWebView", "CKContainer", "NSURLConnection"
        ]
        let pattern = try NSRegularExpression(pattern: #"\b("# + apis.joined(separator: "|") + #")\b"#)
        var offenders: [String] = []
        var seen: Set<String> = []
        for file in try SourceTree.everySwiftFile() {
            let path = SourceTree.relativePath(file)
            for (number, line) in try Self.codeLines(file)
                where pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
            {
                seen.insert(path)
                if !Self.networkCallSites.contains(path) { offenders.append("\(path):\(number)") }
            }
        }
        #expect(
            offenders.isEmpty,
            "a new file reaches the network; add it to networkCallSites with a reason: \(offenders)"
        )
        #expect(
            Self.networkCallSites.subtracting(seen).isEmpty,
            "networkCallSites names files that no longer use the network: \(Self.networkCallSites.subtracting(seen))"
        )
    }

    @Test("the plist's Sparkle feed is on the allowlist too")
    func infoPlistFeed_isOnTheAllowlist() throws {
        let plist = SourceTree.sources.appendingPathComponent("Resources/Info.plist")
        let text = try String(contentsOf: plist, encoding: .utf8)
        let feed = try #require(text.components(separatedBy: "<key>SUFeedURL</key>").last?
            .components(separatedBy: "<string>").dropFirst().first?
            .components(separatedBy: "</string>").first)
        #expect(Self.allowedLiteralHosts.contains(URL(string: feed)?.host ?? ""), "\(feed)")
    }

    @Test("no AI service is named anywhere in the app's sources")
    func noAIProviderHosts() throws {
        let hosts = [
            "api.anthropic.com", "api.openai.com", "generativelanguage.googleapis.com", "api.mistral.ai",
            "api.groq.com", "openrouter.ai", "api.cohere.com", "api.cohere.ai", "api.together.xyz",
            "api.perplexity.ai", "api.x.ai", "api.deepseek.com", "api-inference.huggingface.co",
            "openai.azure.com", "bedrock-runtime", "api.fireworks.ai", "api.replicate.com"
        ]
        var offenders: [String] = []
        for file in try Self.scannedFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            for host in hosts where text.contains(host) {
                offenders.append("\(SourceTree.relativePath(file)): \(host)")
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    @Test("the update feed is on the allowlist, and the guide names it and the download host")
    func updateHosts() throws {
        let allowed: Set = ["github.com", "copypesto.net"]
        let plist = try String(
            contentsOf: SourceTree.repositoryRoot.appendingPathComponent("Sources/Resources/Info.plist"),
            encoding: .utf8
        )
        let feed = try #require(
            plist.range(of: #"(?<=<key>SUFeedURL</key>\s{0,20}<string>)[^<]+"#, options: .regularExpression)
                .map { String(plist[$0]) }
        )
        let feedHost = try #require(URL(string: feed)?.host)
        #expect(feed.hasPrefix("https://"), "the update feed must be HTTPS")
        #expect(allowed.contains(feedHost), "the update feed is on \(feedHost)")
        let guide = try String(
            contentsOf: SourceTree.repositoryRoot.appendingPathComponent("docs/guide/privacy-and-security.md"),
            encoding: .utf8
        )
        for host in allowed {
            #expect(guide.contains(host), "the privacy guide does not name \(host)")
        }
    }
}
