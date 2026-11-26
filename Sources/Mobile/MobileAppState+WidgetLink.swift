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

    struct LinkedSettings: Equatable {
        let target: AppLink
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
        if url.isFileURL {
            return openCollectionFile(url) ? .shown : .ignored
        }
        if let appLink = AppLink.target(in: url) {
            return openAppLink(appLink, url: url)
        }
        guard let target = WidgetLink.target(in: url) else { return .ignored }
        boot()
        if isHistoryLockedNow() {
            heldLink = url
            return .ignored
        }
        guard let context = historyContainer?.mainContext else { return .ignored }
        let id = target.id
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let item = try? context.fetch(descriptor).first, WidgetSnapshotSelection.isEligible(
            item,
            locked: LockedCollections.current()
        ) else {
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

    private func openAppLink(_ appLink: AppLink, url: URL) -> LinkOutcome {
        boot()
        if appLink == .unlock {
            if isHistoryLockedNow() {
                Task { await unlockHistory() }
            }
            return .shown
        }
        if isHistoryLockedNow() {
            heldLink = url
            return .ignored
        }
        linkedSettings = LinkedSettings(target: appLink, serial: (linkedSettings?.serial ?? 0) + 1)
        return .shown
    }

    private func show(_ id: UUID, opensDetail: Bool) {
        linkedClip = LinkedClip(id: id, opensDetail: opensDetail, serial: (linkedClip?.serial ?? 0) + 1)
    }
}
