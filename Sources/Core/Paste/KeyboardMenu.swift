// SPDX-License-Identifier: MIT
import Foundation

/// What Pesto's keyboard shows (ADR 0061): one list, Pinned, then Snippets, then Recent. Without Full Access iOS keeps
/// the shared container and the shared Keychain group closed to a keyboard, so the set is not even asked for.
public struct KeyboardMenu: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case restricted
        /// No set, or one that would not open: Insert from Pesto is off, or Pesto has not written it yet.
        case unavailable
        case empty
        case ready
    }

    public let state: State
    public let groups: [QuickInsertMenu.Group]

    public init(hasFullAccess: Bool, loadSet: () -> QuickInsertSet?) {
        guard hasFullAccess else {
            state = .restricted
            groups = []
            return
        }
        let menu = QuickInsertMenu(set: loadSet())
        groups = menu.groups(matching: "")
        state = switch menu.state {
        case .unavailable: .unavailable
        case .empty: .empty
        case .ready: .ready
        }
    }
}
