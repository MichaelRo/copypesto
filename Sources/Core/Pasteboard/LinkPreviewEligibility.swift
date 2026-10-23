// SPDX-License-Identifier: MIT
import Foundation

/// A link preview means Pesto requests the page, so the site sees the request. That is fine for an ordinary public
/// page and wrong for a one-time link (a password reset, an email verification, an unsubscribe), for anything that
/// carries a token, and for addresses on this Mac or its network.
public enum LinkPreviewEligibility {
    private static let secretParameterNames: Set<String> = [
        "token", "access_token", "id_token", "refresh_token", "auth", "authorization", "key", "api_key", "apikey",
        "sig", "signature", "code", "otp", "password", "passwd", "secret", "session", "sessionid", "sid", "jwt",
        "ticket", "magic", "reset", "verify", "confirm", "confirmation", "invite", "unsubscribe"
    ]

    /// A cloud store signs a download by adding parameters with these prefixes or names.
    private static let signedParameterPrefixes = ["x-amz-", "x-goog-", "x-ms-", "x-oss-"]
    private static let signedParameterNames: Set<String> = ["rlkey", "policy", "key-pair-id", "se", "sktid"]

    /// Sites where the address itself is the permission to open the page: anyone with the link can read it.
    private static let sharedDocumentHosts = [
        "docs.google.com", "drive.google.com", "notion.so", "notion.site", "slack.com", "figma.com", "1drv.ms",
        "onedrive.live.com", "wetransfer.com", "we.tl", "dropbox.com", "box.com", "airtable.com", "miro.com"
    ]

    private static let actionPathHints = [
        "reset-password", "reset_password", "/reset", "/verify", "/confirm", "/unsubscribe", "/magic", "/oauth",
        "/activate", "/invite"
    ]

    /// The address a preview would request: the link itself, or the address inside a Google or Outlook redirect
    /// wrapper. Both are judged, because the wrapper's own address says nothing about where it points.
    public static func fetchTarget(for url: URL) -> URL? {
        guard isEligible(url) else { return nil }
        let target = URLRedirectUnwrapper.unwrap(url)
        return isEligible(target) ? target : nil
    }

    public static func isEligible(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil,
              isPublicHost(host) else { return false }
        if sharedDocumentHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return false }
        let path = url.path.lowercased()
        if actionPathHints.contains(where: { path.contains($0) }) { return false }
        let names = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map { $0.name.lowercased() }
        return !(names ?? []).contains {
            secretParameterNames.contains($0) || signedParameterNames.contains($0)
                || signedParameterPrefixes.contains(where: $0.hasPrefix)
        }
    }

    /// A host is either a plain dotted-decimal address or a DNS name whose last label has a letter. Everything else is
    /// refused, because `127.1`, `0x7f.0.0.1`, `0177.0.0.1` and `2130706433` all reach loopback through the system's
    /// address parser while a string comparison calls them public.
    private static func isPublicHost(_ host: String) -> Bool {
        if host.contains(":") { return false } // an IPv6 literal
        if host == "localhost" || ["local", "internal", "localdomain", "lan", "home", "corp"].contains(where: {
            host.hasSuffix("." + $0)
        }) { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2,
              labels.allSatisfy(isDNSLabel) else { return false } // a single label is an intranet host
        if labels.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }) {
            guard let octets = ipv4Octets(labels) else { return false }
            return !isPrivate(octets)
        }
        return labels.last.map { $0.contains(where: \.isASCIILetter) } ?? false
    }

    private static func isDNSLabel(_ label: Substring) -> Bool {
        !label.isEmpty && label.count <= 63 && label.allSatisfy { $0.isASCIIDigit || $0.isASCIILetter || $0 == "-" }
    }

    private static func ipv4Octets(_ labels: [Substring]) -> [Int]? {
        guard labels.count == 4 else { return nil }
        let octets = labels.compactMap { label -> Int? in
            guard label == "0" || !label.hasPrefix("0") else { return nil } // 0177 is octal to the system parser
            return Int(label).flatMap { (0...255).contains($0) ? $0 : nil }
        }
        return octets.count == 4 ? octets : nil
    }

    private static func isPrivate(_ octets: [Int]) -> Bool {
        let (first, second) = (octets[0], octets[1])
        return first == 0 || first == 10 || first == 127
            || (first == 169 && second == 254)
            || (first == 172 && (16...31).contains(second))
            || (first == 192 && second == 168)
            || (first == 100 && (64...127).contains(second))
    }
}

private extension Character {
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }

    var isASCIILetter: Bool {
        isASCII && isLetter
    }
}
