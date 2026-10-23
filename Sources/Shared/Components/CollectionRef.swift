// SPDX-License-Identifier: MIT
import Foundation

/// Lightweight value type passed from GridView into ClipboardCard to describe an
/// available collection target. Replaces the previous named-tuple which required
/// `swiftlint:disable large_tuple` suppressions at every call site.
struct CollectionRef: Identifiable, Hashable {
    let id: UUID
    let name: String
    let symbolName: String
}
