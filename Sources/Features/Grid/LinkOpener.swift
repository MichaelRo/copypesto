// SPDX-License-Identifier: MIT
import AppKit
import PestoCore

/// Carries out `LinkOpenPolicy` for a link clip, from the card's menu and from its VoiceOver action.
enum LinkOpener {
    static func perform(_ action: LinkOpenPolicy.Action) {
        switch action {
        case let .openInBrowser(url): NSWorkspace.shared.open(url)
        case let .revealInFinder(url): NSWorkspace.shared.activateFileViewerSelecting([url])
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
