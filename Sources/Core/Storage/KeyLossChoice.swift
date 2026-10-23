// SPDX-License-Identifier: MIT

/// The buttons of the dialog shown when the key to an existing history is missing or does not open it.
public enum KeyLossChoice: Equatable, Sendable {
    case quit
    case startEmpty
    case restoreFromBackup

    /// A button index counted from the first button; anything else is Quit, which leaves the history alone.
    public init(buttonIndex: Int) {
        self = switch buttonIndex {
        case 1: .startEmpty
        case 2: .restoreFromBackup
        default: .quit
        }
    }

    /// Wipes the unreadable history at once. Restore from Backup wipes only after a backup has been opened and the
    /// person
    /// has confirmed, in one step with the restore, so a wrong passphrase or a cancelled picker changes nothing.
    public var startsOver: Bool {
        self == .startEmpty
    }

    public var opensRestore: Bool {
        self == .restoreFromBackup
    }
}
