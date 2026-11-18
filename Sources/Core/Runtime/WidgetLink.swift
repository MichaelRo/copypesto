// SPDX-License-Identifier: MIT
import Foundation

/// The links a clip on the iOS widget opens (ADR 0052): `pesto://clip/<UUID>` copies it, `…/show` opens it in Pesto
/// and `…/open` opens a link clip in the browser. Any other shape, an added query, fragment, port, user or path part,
/// or an id that is not a UUID, is not a widget link.
public enum WidgetLink {
    public enum Action: String, CaseIterable, Sendable {
        case copy
        case show
        case open
    }

    public struct Target: Equatable, Sendable {
        public let id: UUID
        public let action: Action

        public init(id: UUID, action: Action) {
            self.id = id
            self.action = action
        }
    }

    public static let host = "clip"

    public static func url(for id: UUID, action: Action = .copy) -> URL {
        var components = URLComponents()
        components.scheme = AppIdentity.urlScheme
        components.host = host
        components.path = "/" + id.uuidString + (action == .copy ? "" : "/" + action.rawValue)
        return components.url ?? URL(fileURLWithPath: "/")
    }

    public static func target(in url: URL) -> Target? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == AppIdentity.urlScheme, components.host == host,
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil else { return nil }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 || parts.count == 3, parts[0].isEmpty, parts[1].count == 36,
              let id = UUID(uuidString: parts[1]) else { return nil }
        guard parts.count == 3 else { return Target(id: id, action: .copy) }
        guard let action = Action(rawValue: parts[2]), action != .copy else { return nil }
        return Target(id: id, action: action)
    }

    public static func clipID(in url: URL) -> UUID? {
        target(in: url).flatMap { $0.action == .copy ? $0.id : nil }
    }
}
