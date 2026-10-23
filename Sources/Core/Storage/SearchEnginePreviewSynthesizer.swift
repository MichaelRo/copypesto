// SPDX-License-Identifier: MIT
import Foundation

public enum SearchEnginePreviewSynthesizer {
    public struct Preview: Equatable, Sendable {
        public let title: String
        public let siteName: String

        public init(title: String, siteName: String) {
            self.title = title
            self.siteName = siteName
        }
    }

    public static func synthesize(_ url: URL) -> Preview? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else { return nil }

        if let searchPreview = synthesizeSearch(host: host, components: components) {
            return searchPreview
        }
        return synthesizeGoogleWorkspace(host: host, path: components.path.lowercased())
    }

    private static func synthesizeSearch(host: String, components: URLComponents) -> Preview? {
        if isGoogleDomain(host), components.path == "/search" {
            let query = cleanQuery(components.queryItems?.first(where: { $0.name == "q" })?.value)
            let title = if let query { "\(query) — Google Search" } else { "Google Search" }
            return Preview(title: title, siteName: "Google")
        }
        if host == "bing.com" || host.hasSuffix(".bing.com"), components.path == "/search" {
            let query = cleanQuery(components.queryItems?.first(where: { $0.name == "q" })?.value)
            let title = if let query { "\(query) — Bing Search" } else { "Bing Search" }
            return Preview(title: title, siteName: "Bing")
        }
        if host == "duckduckgo.com" || host.hasSuffix(".duckduckgo.com") {
            let query = cleanQuery(components.queryItems?.first(where: { $0.name == "q" })?.value)
            let title = if let query { "\(query) — DuckDuckGo" } else { "DuckDuckGo" }
            return Preview(title: title, siteName: "DuckDuckGo")
        }
        return nil
    }

    private static func synthesizeGoogleWorkspace(host: String, path: String) -> Preview? {
        if host == "docs.google.com" || host == "drive.google.com" {
            if path.contains("/document/") {
                return Preview(title: "Google Docs Document", siteName: "Google Docs")
            }
            if path.contains("/spreadsheets/") {
                return Preview(title: "Google Sheets Spreadsheet", siteName: "Google Sheets")
            }
            if path.contains("/presentation/") {
                return Preview(title: "Google Slides Presentation", siteName: "Google Slides")
            }
            if host == "drive.google.com" || path.contains("/drive/") {
                return Preview(title: "Google Drive", siteName: "Google Drive")
            }
            return Preview(title: "Google Workspace", siteName: "Google Workspace")
        }
        if host == "accounts.google.com" {
            return Preview(title: "Google Account Sign-In", siteName: "Google")
        }
        return nil
    }

    private static func cleanQuery(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.replacingOccurrences(of: "+", with: " ").trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isGoogleDomain(_ host: String) -> Bool {
        host == "google.com" || host.hasSuffix(".google.com")
            || host.contains(".google.")
            || host.hasPrefix("google.")
    }
}
