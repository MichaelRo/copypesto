// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import UIKit

/// The clipboard when Pesto comes to the front: something new is offered (the Paste button, no prompt) or, with "Add
/// copies when Pesto opens" on, added at once (iOS asks for permission). One change count is handled once, and what
/// Pesto itself wrote (`MobileClipboard.write` records its count) is never offered.
extension MobileAppState {
    func clipboardDidBecomeActive(
        pasteboard: UIPasteboard = AppPasteboard.general, defaults: UserDefaults = AppDefaults.store
    ) async {
        guard historyContainer != nil, !isHistoryLockedNow() else { return }
        let count = pasteboard.changeCount
        let decision = ClipboardOffer.decide(
            changeCount: count,
            lastSeen: defaults.value(for: Setting.lastSeenPasteboardChange),
            hasContent: pasteboard.hasStrings || pasteboard.hasURLs || pasteboard.hasImages,
            addsAutomatically: defaults.value(for: Setting.addsCopiesOnOpen)
        )
        switch decision {
        case .nothing:
            return
        case .offer:
            defaults.set(count, for: Setting.lastSeenPasteboardChange)
            clipboardOfferCount = count
        case .addNow:
            defaults.set(count, for: Setting.lastSeenPasteboardChange)
            clipboardOfferCount = nil
            await add(
                from: pasteboard.itemProviders,
                method: .paste,
                pasteboardTypes: pasteboard.types,
                into: resolvedDefaultPasteCollectionID(defaults: defaults),
                assignCollectionOnlyIfUnfiled: true,
                reportEmpty: false
            )
        }
    }

    func takeClipboardOffer(_ providers: [NSItemProvider], defaults: UserDefaults = AppDefaults.store) async {
        clipboardOfferCount = nil
        await add(
            from: providers,
            method: .paste,
            into: resolvedDefaultPasteCollectionID(defaults: defaults),
            assignCollectionOnlyIfUnfiled: true
        )
    }

    func dismissClipboardOffer() {
        clipboardOfferCount = nil
    }
}
