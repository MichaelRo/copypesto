// SPDX-License-Identifier: MIT
import PestoCore

extension NSFWMode {
    /// What the picker's tile says: a verb, in Title Case, and translatable (the raw value is a stored key).
    var title: String {
        switch self {
        case .blur: String(localized: "Blur")
        case .hide: String(localized: "Hide")
        case .show: String(localized: "Show")
        }
    }
}
