// SPDX-License-Identifier: MIT
#if DEBUG
import Foundation
import os
import PestoCore
import SwiftData
import UIKit
import UniformTypeIdentifiers

/// A clip of each kind for a `-UITestMode` launch, added through ingest like any capture, then one pinned and one in a
/// collection through the app's own actions. A launch with `PESTO_UITEST_SEED=empty` starts with none.
enum MobileSeed {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "MobileSeed")
    static let noteText = "Packing list: passport, charger, the blue notebook"
    static let shortText = "Gate B7"
    static let linkText = "https://copypesto.net/guide/"
    static let colorText = "#3F7D4E"
    static let secretText = "ghp_8fK2mQ9xLr4TzW7nB1vC6yH3sJ5dE0aGpU2i"
    static let codeText = "func blend(_ basil: [Leaf]) -> Pesto {\n    let crushed = basil.map(\\.crushed)\n"
        + "    return Pesto(leaves: crushed, oil: .olive)\n}"
    static let longText = "Pesto night at Dana's, Friday at 7:00 pm. Bring the basil and the pecorino. "
        + "Toast the pine nuts first, crush the basil with sea salt and garlic in the mortar, "
        + "then fold in the cheese and the oil at the very end."
    static let collectionName = "Trip"
    static let pinnedID = UUID(uuidString: "5E3D0A51-0000-4000-8000-000000000001") ?? UUID()
    static let filedID = UUID(uuidString: "5E3D0A51-0000-4000-8000-000000000002") ?? UUID()

    @MainActor
    static func runIfAsked(state: MobileAppState, configuration: RuntimeConfiguration = .current) async {
        guard configuration.mode == .uiTest, configuration.seed != .empty,
              let service = state.storageService else { return }
        for (capture, id) in captures(now: .now) {
            do {
                try await service.ingest(capture, preferredItemID: id)
            } catch {
                logger.error("A seed clip was not added: \(error.localizedDescription, privacy: .public)")
            }
        }
        for number in 0..<extraClipCount {
            let text = "Filler clip \(number): a line to make the grid scroll"
            guard let capture = ClipCapture.text(text, at: .now) else { continue }
            try? await service.ingest(capture)
        }
        await service.waitForBackgroundWork()
        await arrange(state)
        if let copied = ProcessInfo.processInfo.environment["PESTO_UITEST_CLIPBOARD"] {
            MobileClipboard.write(.text(copied), protected: false)
            AppDefaults.store.set(-1, for: Setting.lastSeenPasteboardChange)
            await state.clipboardDidBecomeActive()
        }
    }

    /// `PESTO_UITEST_EXTRA_CLIPS=<n>` adds n plain notes, so a UI test can scroll the grid.
    private static var extraClipCount: Int {
        ProcessInfo.processInfo.environment["PESTO_UITEST_EXTRA_CLIPS"].flatMap(Int.init) ?? 0
    }

    @MainActor
    private static func arrange(_ state: MobileAppState) async {
        await state.togglePin(pinnedID)
        state.dismissAutoFillTip()
        AppDefaults.store.set(false, for: Setting.autoFillTipShown)
        guard let board = state.addCollection(named: collectionName, existing: []),
              let context = state.historyContainer?.mainContext else { return }
        let id = filedID
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        do {
            if let item = try context.fetch(descriptor).first {
                state.moveToCollection(item, collectionID: board.id)
            }
        } catch {
            logger.error("The seed clip was not filed: \(error.localizedDescription, privacy: .public)")
        }
        state.historyStore?.refresh()
    }

    /// Oldest first, a second apart, so the library's order is the same on every launch.
    static func captures(now: Date) -> [(PasteboardCapture, UUID?)] {
        let earlier = { (seconds: Double) in now.addingTimeInterval(-seconds) }
        let png = UTType.png.identifier
        let list: [(PasteboardCapture?, UUID?)] = [
            (ClipCapture.picture(picture(width: 240, height: 240), typeIdentifier: png, at: earlier(10)), nil),
            (ClipCapture.picture(picture(width: 360, height: 240), typeIdentifier: png, at: earlier(9)), nil),
            (ClipCapture.text(longText, at: earlier(8)), nil),
            (ClipCapture.text(codeText, at: earlier(7)), nil),
            (ClipCapture.text(secretText, at: earlier(6)), nil),
            (ClipCapture.text(colorText, at: earlier(5)), nil),
            (ClipCapture.text(linkText, at: earlier(4)), filedID),
            (ClipCapture.text(shortText, at: earlier(3)), pinnedID),
            (ClipCapture.text(noteText, at: earlier(1)), nil)
        ]
        return list.compactMap { capture, id in capture.map { ($0, id) } }
    }

    private static func picture(width: CGFloat, height: CGFloat) -> Data {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            UIColor(red: 0.25, green: 0.49, blue: 0.31, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.96, green: 0.93, blue: 0.82, alpha: 1).setFill()
            let side = min(width, height) * 0.6
            context.cgContext.fillEllipse(in: CGRect(
                x: (width - side) / 2, y: (height - side) / 2, width: side, height: side
            ))
        }
    }
}
#endif
