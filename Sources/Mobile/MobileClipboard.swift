// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import UIKit
import UniformTypeIdentifiers

/// The one place the iOS app writes to the clipboard. A secret stays on this device (never Universal Clipboard) and
/// leaves the clipboard after `secretLifetime`, as a password manager's copy does.
enum MobileClipboard {
    static let secretLifetime: TimeInterval = 120

    static func options(protected: Bool, now: Date = .now) -> [UIPasteboard.OptionsKey: Any] {
        guard protected else { return [:] }
        return [.localOnly: true, .expirationDate: now.addingTimeInterval(secretLifetime)]
    }

    static func items(for content: ClipContent) -> [[String: Any]] {
        switch content {
        case let .text(text):
            [[UTType.utf8PlainText.identifier: text]]
        case let .link(url, text):
            [[UTType.url.identifier: url, UTType.utf8PlainText.identifier: text]]
        case let .picture(data, typeIdentifier):
            [[typeIdentifier: data]]
        }
    }

    @MainActor
    static func write(
        _ content: ClipContent, protected: Bool, to pasteboard: UIPasteboard = AppPasteboard.general, now: Date = .now,
        defaults: UserDefaults = AppDefaults.store
    ) {
        pasteboard.setItems(items(for: content), options: options(protected: protected, now: now))
        defaults.set(pasteboard.changeCount, for: Setting.lastSeenPasteboardChange)
    }
}
