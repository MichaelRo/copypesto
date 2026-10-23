// SPDX-License-Identifier: MIT
import Foundation

public enum URLRedirectUnwrapper {
    public static func unwrap(_ url: URL) -> URL {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else { return url }

        // Google search redirect wrapper: google.*/url?q=... or ?url=...
        if isGoogleDomain(host), components.path == "/url" {
            if let targetString = components.queryItems?.first(where: { $0.name == "q" || $0.name == "url" })?.value,
               let targetURL = URL(string: targetString),
               let scheme = targetURL.scheme?.lowercased(),
               scheme == "http" || scheme == "https"
            {
                return targetURL
            }
        }

        // Outlook Safelinks: *.safelinks.protection.outlook.com/?url=...
        if host.hasSuffix("safelinks.protection.outlook.com") {
            if let targetString = components.queryItems?.first(where: { $0.name == "url" })?.value,
               let targetURL = URL(string: targetString),
               let scheme = targetURL.scheme?.lowercased(),
               scheme == "http" || scheme == "https"
            {
                return targetURL
            }
        }

        return url
    }

    private static func isGoogleDomain(_ host: String) -> Bool {
        host
            .range(of: #"^(www\.)?google\.(com|co\.[a-z]{2}|com\.[a-z]{2}|[a-z]{2})$"#, options: .regularExpression) !=
            nil
    }
}
