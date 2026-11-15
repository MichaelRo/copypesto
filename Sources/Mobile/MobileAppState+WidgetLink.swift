// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftData

/// A clip tapped on the widget (ADR 0052): `pesto://clip/<UUID>` and nothing else. A clip the widget may still show is
/// copied through the library's one copy path and shown; an unknown or no-longer-eligible id only opens the library.
extension MobileAppState {
    struct LinkedClip: Equatable {
        let id: UUID
        let serial: Int
    }

    /// True when the link copied a clip. Any other URL is ignored.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let id = WidgetLink.clipID(in: url) else { return false }
        boot()
        guard let context = historyContainer?.mainContext else { return false }
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let item = try? context.fetch(descriptor).first, WidgetSnapshotSelection.isEligible(item),
              copy(item) else { return false }
        linkedClip = LinkedClip(id: id, serial: (linkedClip?.serial ?? 0) + 1)
        return true
    }
}
