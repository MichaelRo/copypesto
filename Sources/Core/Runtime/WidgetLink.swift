// SPDX-License-Identifier: MIT
import Foundation

/// The link a clip on the iOS widget opens (ADR 0052): `pesto://clip/<UUID>`, and nothing else. Any other shape, an
/// added query, fragment, port, user or path part, or an id that is not a UUID, is not a widget link.
public enum WidgetLink {
    public static let host = "clip"

    public static func url(for id: UUID) -> URL {
        var components = URLComponents()
        components.scheme = AppIdentity.urlScheme
        components.host = host
        components.path = "/" + id.uuidString
        return components.url ?? URL(fileURLWithPath: "/")
    }

    public static func clipID(in url: URL) -> UUID? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == AppIdentity.urlScheme, components.host == host,
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil else { return nil }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].isEmpty, parts[1].count == 36 else { return nil }
        return UUID(uuidString: String(parts[1]))
    }
}
