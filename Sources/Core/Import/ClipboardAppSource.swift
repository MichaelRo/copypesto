// SPDX-License-Identifier: MIT
import Foundation

public enum ClipboardAppSource: String, CaseIterable, Sendable {
    case maccy
    case alfred
    case cleanclip
    case pastenow
    case copyclip
    case pastepal
    case pastebot
    case clipy
    case flycut
    case unclutter

    public var name: String {
        switch self {
        case .maccy: "Maccy"
        case .alfred: "Alfred"
        case .cleanclip: "CleanClip"
        case .pastenow: "PasteNow"
        case .copyclip: "CopyClip"
        case .pastepal: "PastePal"
        case .pastebot: "Pastebot"
        case .clipy: "Clipy"
        case .flycut: "Flycut"
        case .unclutter: "Unclutter"
        }
    }

    public var defaultDatabaseURL: URL {
        switch self {
        case .maccy: MaccyLibraryReader.defaultDatabaseURL
        case .alfred: AlfredLibraryReader.defaultDatabaseURL
        case .cleanclip: CleanClipLibraryReader.defaultDatabaseURL
        case .pastenow: PasteNowLibraryReader.defaultDatabaseURL
        case .copyclip: CopyClipLibraryReader.defaultDatabaseURL
        case .pastepal: PastePalLibraryReader.defaultDatabaseURL
        case .pastebot: PastebotLibraryReader.defaultDatabaseURL
        case .clipy: ClipyLibraryReader.defaultDatabaseURL
        case .flycut: FlycutLibraryReader.defaultDatabaseURL
        case .unclutter: UnclutterLibraryReader.defaultDatabaseURL
        }
    }

    public var canChooseDirectories: Bool {
        self == .unclutter
    }

    public func read(databaseAt url: URL) throws -> ClipboardAppLibrary {
        switch self {
        case .maccy: try MaccyLibraryReader.read(databaseAt: url)
        case .alfred: try AlfredLibraryReader.read(databaseAt: url)
        case .cleanclip: try CleanClipLibraryReader.read(databaseAt: url)
        case .pastenow: try PasteNowLibraryReader.read(databaseAt: url)
        case .copyclip: try CopyClipLibraryReader.read(databaseAt: url)
        case .pastepal: try PastePalLibraryReader.read(databaseAt: url)
        case .pastebot: try PastebotLibraryReader.read(databaseAt: url)
        case .clipy: try ClipyLibraryReader.read(databaseAt: url)
        case .flycut: try FlycutLibraryReader.read(databaseAt: url)
        case .unclutter: try UnclutterLibraryReader.read(databaseAt: url)
        }
    }
}
