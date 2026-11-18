// SPDX-License-Identifier: MIT
import AppIntents
import Foundation
import os
import PestoCore
import UIKit
import UniformTypeIdentifiers

/// A tile's in-place copy (ADR 0052). It runs in the widget's process, opens the sealed snapshot, and puts that clip's
/// whole text on the clipboard: only a clip the snapshot carries whole text for, so nothing is cut short and nothing
/// beyond the snapshot is read. Anything else is copied by opening Pesto.
struct CopyClipIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Clip"
    static let isDiscoverable = false

    /// Measured in the iOS 27.2 simulator: a write from the widget's process reaches the system clipboard.
    static let copiesInPlace = true

    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Widget")

    @Parameter(title: "Clip") var clipID: String

    init() {}

    init(clipID: UUID) {
        self.clipID = clipID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: clipID), let clip = WidgetSnapshotReader.read()?.clip(id: id),
              let text = clip.fullText else
        {
            Self.logger.error("A widget copy found no clip it may copy")
            return .result()
        }
        await MainActor.run { Self.write(text, kind: clip.kind, to: AppPasteboard.general) }
        WidgetCopyRecord.save(id, at: .now)
        return .result()
    }

    @MainActor
    static func write(_ text: String, kind: ClipboardType, to pasteboard: UIPasteboard) {
        pasteboard.setItems([item(text, kind: kind)], options: [:])
    }

    /// The text, and for a link clip that is one web address, the address too, as the app's copy writes a link.
    static func item(_ text: String, kind: ClipboardType) -> [String: Any] {
        var item: [String: Any] = [UTType.utf8PlainText.identifier: text]
        if kind == .url, let url = WidgetTap.webURL(in: text) { item[UTType.url.identifier] = url }
        return item
    }
}
