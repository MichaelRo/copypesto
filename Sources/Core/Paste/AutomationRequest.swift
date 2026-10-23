// SPDX-License-Identifier: MIT
import Foundation

/// What a `pesto://` link asks for. A link that names no action, or leaves out what its action needs, is no request:
/// a bare `pesto://clear` on a web page must not wipe the history.
public enum AutomationRequest: Equatable, Sendable {
    case open
    case list
    case search(String?)
    case paste(UUID)
    case pin(UUID)
    case summary(UUID)
    case collection(String)
    case clear(ClearRange)

    public init?(url: URL) {
        guard url.scheme == "pesto", let action = AutomationAction(host: url.host) else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        let id = value("id").flatMap { UUID(uuidString: $0) }
        switch action {
        case .open: self = .open
        case .list: self = .list
        case .search: self = .search(value("q").flatMap { $0.isEmpty ? nil : $0 })
        case .paste, .pin, .summary: guard let request = Self.clipRequest(action, id: id) else { return nil }
            self = request
        case .collection:
            guard let name = value("name"), !name.isEmpty else { return nil }
            self = .collection(name)
        case .clear:
            guard let range = ClearRange(automationName: value("range")) else { return nil }
            self = .clear(range)
        }
    }

    private static func clipRequest(_ action: AutomationAction, id: UUID?) -> AutomationRequest? {
        guard let id else { return nil }
        switch action {
        case .paste: return .paste(id)
        case .pin: return .pin(id)
        case .summary: return .summary(id)
        default: return nil
        }
    }
}
