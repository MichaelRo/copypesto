// SPDX-License-Identifier: MIT
#if DEBUG
import Foundation
import os
import PestoCore
import UIKit
import UniformTypeIdentifiers

/// A handful of clips of each kind for a `-UITestMode` launch, added through ingest like any capture. A launch with
/// `PESTO_UITEST_SEED=empty` starts with none.
enum MobileSeed {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "MobileSeed")
    static let noteText = "Packing list: passport, charger, the blue notebook"
    static let linkText = "https://copypesto.net/guide/"
    static let colorText = "#3F7D4E"
    static let secretText = "ghp_8fK2mQ9xLr4TzW7nB1vC6yH3sJ5dE0aGpU2i"

    static func runIfAsked(service: StorageService, configuration: RuntimeConfiguration = .current) async {
        guard configuration.mode == .uiTest, configuration.seed != .empty else { return }
        for capture in captures(now: .now) {
            do {
                try await service.ingest(capture)
            } catch {
                logger.error("A seed clip was not added: \(error.localizedDescription, privacy: .public)")
            }
        }
        await service.waitForBackgroundWork()
    }

    /// Oldest first, a second apart, so the library's order is the same on every launch.
    static func captures(now: Date) -> [PasteboardCapture] {
        let earlier = { (seconds: Double) in now.addingTimeInterval(-seconds) }
        return [
            ClipCapture.picture(picture(), typeIdentifier: UTType.png.identifier, at: earlier(5)),
            ClipCapture.text(secretText, at: earlier(4)),
            ClipCapture.text(colorText, at: earlier(3)),
            ClipCapture.text(linkText, at: earlier(2)),
            ClipCapture.text(noteText, at: earlier(1))
        ].compactMap(\.self)
    }

    private static func picture() -> Data {
        let size = CGSize(width: 240, height: 160)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            UIColor(red: 0.25, green: 0.49, blue: 0.31, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.96, green: 0.93, blue: 0.82, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 70, y: 30, width: 100, height: 100))
        }
    }
}
#endif
