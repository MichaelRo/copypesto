// SPDX-License-Identifier: MIT
import Foundation

/// What a link clip's "Open" does. A web address opens in the browser; a `file:` address is shown in Finder rather
/// than handed to `NSWorkspace.open`, which would launch an application or a script under a button that says
/// "Open in Browser" (R-05); any other scheme does nothing.
public enum LinkOpenPolicy {
    public enum Action: Equatable, Sendable {
        case openInBrowser(URL)
        case revealInFinder(URL)
        case none
    }

    public static func action(for text: String) -> Action {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return .none }
        switch scheme {
        case "http", "https":
            return url.host?.isEmpty == false ? .openInBrowser(url) : .none
        case "file":
            return url.path.isEmpty || url.path == "/" ? .none : .revealInFinder(URL(filePath: url.path))
        default:
            return .none
        }
    }
}
