// SPDX-License-Identifier: MIT
import Foundation

public struct LinkDisplay: Equatable, Sendable {
    public let host: String
    public let rest: String

    public init(host: String, rest: String) {
        self.host = host
        self.rest = rest
    }

    /// The host the address really goes to, read by `URLComponents` and never from a page's own name for itself, and
    /// the port, path, query and fragment after it. User info (`paypal.com@evil.example`) is dropped, so the host shown
    /// is the one a click reaches. Nil when there is no host to lead with (mailto:, file:, text that is not one link).
    public static func parse(_ text: String) -> LinkDisplay? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        var components = URLComponents(string: trimmed)
        if components?.host?.isEmpty ?? true, !trimmed.contains(":") {
            components = URLComponents(string: "https://" + trimmed)
            guard components?.host?.contains(".") == true else { return nil }
        }
        guard let components, let host = components.host?.lowercased(), !host.isEmpty else { return nil }
        var rest = components.port.map { ":\($0)" } ?? ""
        if components.path != "/" { rest += components.path }
        if let query = components.query { rest += "?" + query }
        if let fragment = components.fragment { rest += "#" + fragment }
        return LinkDisplay(host: host, rest: rest)
    }
}
