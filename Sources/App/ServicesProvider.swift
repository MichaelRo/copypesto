// SPDX-License-Identifier: MIT
import AppKit
import PestoCore

/// The "Copy to Pesto" item in other apps' Services menu: selected text goes to the clipboard, where the watcher
/// records it like any other copy. It reads nothing from Pesto's history, so it works while the history is locked.
@MainActor
final class ServicesProvider: NSObject {
    static let shared = ServicesProvider()

    /// Copies the text on `source` to `destination`. False when the service pasteboard holds no text.
    @discardableResult
    static func copyText(from source: NSPasteboard, to destination: NSPasteboard) -> Bool {
        guard let text = source.string(forType: .string), !text.isEmpty else { return false }
        PasteboardProtection.beginWrite(on: destination, protected: false)
        destination.setString(text, forType: .string)
        return true
    }

    /// The name in Info.plist's `NSServices` entry (`NSMessage`).
    @objc
    func copyToPesto(
        _ pasteboard: NSPasteboard,
        userData _: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard Self.copyText(from: pasteboard, to: AppPasteboard.general) else {
            error.pointee = "Select some text to copy to Pesto." as NSString
            return
        }
    }
}
