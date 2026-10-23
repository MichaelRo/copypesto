// SPDX-License-Identifier: MIT
import Foundation

/// What started a paste. Its label goes into the system log (which persists), so it can only ever name the
/// trigger and identify an item by id, never carry clipboard content.
public enum PasteTrigger: Sendable, Equatable {
    case overlaySelect(itemID: UUID)
    case stackAdvance(position: Int)
    case scriptOrURLScheme(itemID: UUID)
    case quickMenu
    case quickPasteLast
    case pastePlainText
    case aiResult
    case pinnedHotkey(slot: Int)

    public var logLabel: String {
        switch self {
        case let .overlaySelect(id): "overlay-select item=\(id.uuidString)"
        case let .stackAdvance(position): "stack-advance position=\(position)"
        case let .scriptOrURLScheme(id): "script-or-url-scheme item=\(id.uuidString)"
        case .quickMenu: "quick-menu"
        case .quickPasteLast: "quick-paste-last"
        case .pastePlainText: "paste-plain-text"
        case .aiResult: "ai-result"
        case let .pinnedHotkey(slot): "pinned-hotkey slot=\(slot)"
        }
    }
}
