// SPDX-License-Identifier: MIT
import Foundation
import UniformTypeIdentifiers

/// The `.pestobackup` file (ADR 0010), declared in both apps' Info.plist as an exported type so the Files picker
/// offers it by name (ADR 0078).
public enum BackupFileType {
    public static let fileExtension = "pestobackup"
    public static let identifier = "\(AppIdentity.bundleID).backup"

    public static var utType: UTType {
        UTType(identifier) ?? UTType(exportedAs: identifier, conformingTo: .data)
    }
}
