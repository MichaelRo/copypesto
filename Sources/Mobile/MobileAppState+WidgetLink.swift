// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftData

/// A clip tapped on the widget (ADR 0052): `pesto://clip/<UUID>` copies it through the library's one copy path,
/// `…/show` opens it in the library, `…/open` hands a link clip's web address to the browser. Only a clip the widget
/// may still show is acted on; an unknown or no-longer-eligible id only opens the library, and any other URL is
/// ignored.
extension MobileAppState {
    struct LinkedClip: Equatable {
        let id: UUID
        let opensDetail: Bool
        let serial: Int
    }

    enum LinkOutcome: Equatable {
        case ignored
        case copied
        case shown
        case openedInBrowser(URL)
    }

    @discardableResult
    func open(_ url: URL) -> LinkOutcome {
        guard let target = WidgetLink.target(in: url) else { return .ignored }
        boot()
        guard let context = historyContainer?.mainContext else { return .ignored }
        let id = target.id
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let item = try? context.fetch(descriptor).first, WidgetSnapshotSelection.isEligible(item) else {
            return .ignored
        }
        switch target.action {
        case .copy:
            guard copy(item) else { return .ignored }
            show(id, opensDetail: false)
            return .copied
        case .open:
            if item.type == .url, let text = item.blob?.decryptedText(), let web = WidgetTap.webURL(in: text) {
                openExternally(web)
                return .openedInBrowser(web)
            }
            show(id, opensDetail: true)
            return .shown
        case .show:
            show(id, opensDetail: true)
            return .shown
        }
    }

    private func show(_ id: UUID, opensDetail: Bool) {
        linkedClip = LinkedClip(id: id, opensDetail: opensDetail, serial: (linkedClip?.serial ?? 0) + 1)
    }
}
