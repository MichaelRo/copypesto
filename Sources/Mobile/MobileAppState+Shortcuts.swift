// SPDX-License-Identifier: MIT
import AppIntents
import Foundation
import os
import PestoCore
import UniformTypeIdentifiers

/// What the Shortcuts actions do, in the app's own process (ADR 0047): Add goes through ingest like any capture, and a
/// search hands out only what `ShortcutClipSearch` offers, so a secret's text never leaves through Shortcuts.
extension MobileAppState {
    enum ShortcutFailure: Error, Equatable, CustomLocalizedStringResourceConvertible {
        case notReady
        case nothingToAdd
        case locked
        case emptyClipboard
        case refused(String)
        case failed

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .notReady: "Pesto is not ready. Open Pesto and try again."
            case .nothingToAdd: "There was nothing Pesto can keep."
            case .locked: "Pesto is locked. Open Pesto to unlock it, then try again."
            case .emptyClipboard: "The clipboard has nothing Pesto can keep."
            case let .refused(message): "\(message)"
            case .failed: "Couldn\u{2019}t add the clip."
            }
        }
    }

    private static let shortcutLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "Shortcuts")

    func addFromShortcut(text: String?, file: Data?, fileType: UTType?) async throws {
        boot()
        guard let service = storageService else { throw ShortcutFailure.notReady }
        guard let capture = Self.shortcutCapture(text: text, file: file, fileType: fileType) else {
            throw ShortcutFailure.nothingToAdd
        }
        do {
            try await service.ingest(capture.with(captureMethod: .shortcut))
        } catch let refusal as ClipSizePolicy.TooLarge {
            throw ShortcutFailure.refused(refusal.message)
        } catch {
            Self.shortcutLogger.error("A shortcut's clip failed: \(error.localizedDescription, privacy: .public)")
            throw ShortcutFailure.failed
        }
    }

    func searchForShortcut(_ query: String, limit: Int = 20) throws -> [ShortcutClip] {
        boot()
        guard let context = historyContainer?.mainContext else { throw ShortcutFailure.notReady }
        guard !isHistoryLockedNow() else { return [] }
        return try ShortcutClipSearch.search(query, in: context, nsfwMode: .current(), limit: limit)
    }

    func shortcutClips(ids: [UUID]) throws -> [ShortcutClip] {
        boot()
        guard let context = historyContainer?.mainContext else { throw ShortcutFailure.notReady }
        guard !isHistoryLockedNow() else { return [] }
        return try ShortcutClipSearch.clips(ids: ids, in: context, nsfwMode: .current())
    }

    static func shortcutCapture(text: String?, file: Data?, fileType: UTType?) -> PasteboardCapture? {
        if let text, let capture = ClipCapture.text(text) { return capture }
        guard let file, !file.isEmpty else { return nil }
        if let type = fileType?.identifier, ClipCapture.storedPictureTypes.contains(type) {
            return ClipCapture.picture(file, typeIdentifier: type)
        }
        if fileType?.conforms(to: .image) ?? true,
           let png = ImageDownsampler.thumbnailPNG(from: file, maxPixel: InboxPolicy.maxConvertedPixel)
        {
            return ClipCapture.picture(png, typeIdentifier: UTType.png.identifier)
        }
        if fileType?.conforms(to: .plainText) == true, let string = String(data: file, encoding: .utf8) {
            return ClipCapture.text(string)
        }
        return nil
    }
}
