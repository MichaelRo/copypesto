// SPDX-License-Identifier: MIT
import Foundation

/// What a compact navigation stack pushes.
struct ClipRoute: Hashable {
    let id: UUID
}

struct CollectionRoute: Hashable {
    let id: UUID
    let name: String
}
