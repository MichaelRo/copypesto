// SPDX-License-Identifier: MIT
import Foundation

public extension ClipboardItem {
    /// "Text" tells nothing the card does not already show, so a plain text clip names the app it came from; the other
    /// kinds keep their label, because it is what sets them apart. An app macOS could not name says nothing either, so
    /// that clip is "Text" again.
    var headerNamesTheApp: Bool {
        customTitle == nil && type == .text && !isRemote && knownSourceAppName != nil
    }

    /// The app's name, unless macOS could not name it ("Unknown app" is a fallback, not a name).
    var knownSourceAppName: String? {
        sourceAppName.flatMap { $0 == SourceAppRecord.unknownDisplayName ? nil : $0 }
    }
}
