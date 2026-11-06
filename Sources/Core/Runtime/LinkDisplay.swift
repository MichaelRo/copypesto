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
    /// the port and path after it, cut at `restLimit`. The query and fragment are never shown: a magic-link or reset
    /// token
    /// lives there, and the old card showed no address at all. User info (`paypal.com@evil.example`) is dropped, so the
    /// host shown
    /// is the one a click reaches. An address typed without a scheme is read as a network-path reference
    /// (`//host/path`),
    /// so nothing here builds a URL to open. Nil when there is no host to lead with (mailto:, file:, text that is not
    /// one link).
    public static func parse(_ text: String) -> LinkDisplay? {
        memo.value(for: text) { read(text) }
    }

    public static let restLimit = 80
    private static let memo = StringMemo<LinkDisplay?>()

    private static func read(_ text: String) -> LinkDisplay? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        var components = URLComponents(string: trimmed)
        if components?.host?.isEmpty ?? true, !trimmed.contains(":") {
            components = URLComponents(string: "//" + trimmed)
            guard components?.host?.contains(".") == true else { return nil }
        }
        guard let components, var host = components.host?.lowercased(), !host.isEmpty else { return nil }
        if host.contains(":"), !host.hasPrefix("[") { host = "[\(host)]" }
        var rest = components.port.map { ":\($0)" } ?? ""
        if components.path != "/" { rest += components.path }
        if rest.count > restLimit { rest = String(rest.prefix(restLimit - 1)) + "\u{2026}" }
        return LinkDisplay(host: host, rest: rest)
    }

    /// Fixed sizes by length: the headline size up to 24 characters of host, the smaller step beyond.
    public static func hostPoints(forLength length: Int) -> Double {
        length <= CardTreatment.headlineLimit ? CardTreatment.headlinePoints : CardTreatment.secondaryPoints
    }

    private static let roomyBudget = 90.0
    private static let gapBetweenHostAndPath = 4.0

    /// Lines for the host (as many as fit, up to the step's most) and then for the path in what is left; the path
    /// gives way before the host is cut.
    public static func lineLimits(
        hostPoints: Double,
        hostMaxLines: Int,
        pathPoints: Double,
        heightBudget: Double
    )
    -> (host: Int, path: Int) {
        let roomy = heightBudget >= roomyBudget
        let hostLine = hostPoints * CardTreatment.lineHeightFactor
        let host = min(max(Int(heightBudget / hostLine), 1), hostMaxLines)
        let left = heightBudget - Double(host) * hostLine - gapBetweenHostAndPath
        let path = min(max(Int(left / (pathPoints * CardTreatment.lineHeightFactor)), 0), roomy ? 3 : 2)
        return (host, path)
    }

    /// The host with a zero-width space after every dot: the only places a host can wrap.
    public static func breakableHost(_ host: String) -> String {
        host.replacingOccurrences(of: ".", with: ".\u{200B}")
    }
}
