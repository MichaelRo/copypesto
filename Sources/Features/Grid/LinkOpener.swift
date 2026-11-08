// SPDX-License-Identifier: MIT
import AppKit
import PestoCore

/// Carries out `LinkOpenPolicy` for a link clip, from the card's menu and from its VoiceOver action.
enum LinkOpener {
    static func perform(
        _ action: LinkOpenPolicy.Action,
        openURL: (URL) -> Void = { NSWorkspace.shared.open($0) },
        revealInFinder: ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }
    ) {
        switch action {
        case let .openInBrowser(url): openURL(url)
        case let .revealInFinder(url): revealInFinder([url])
        case .none: break
        }
    }

    static func title(for action: LinkOpenPolicy.Action) -> String? {
        switch action {
        case .openInBrowser: String(localized: "Open in Browser")
        case .revealInFinder: String(localized: "Show in Finder")
        case .none: nil
        }
    }

    static func symbol(for action: LinkOpenPolicy.Action) -> String {
        if case .revealInFinder = action { return "folder" }
        return "safari"
    }
}
