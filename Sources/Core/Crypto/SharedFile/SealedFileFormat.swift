// SPDX-License-Identifier: MIT
import Foundation

/// What sets one sealed app-group file apart from another (ADR 0051, ADR 0052): its name, an eight-byte magic, a
/// version byte, the purpose string sealed in as associated data, and the most bytes a reader takes.
public struct SealedFileFormat: Equatable, Sendable {
    public let fileName: String
    public let magic: Data
    public let version: UInt8
    public let purpose: Data
    public let maxFileBytes: Int

    public init(fileName: String, magic: String, version: UInt8, purpose: String, maxFileBytes: Int) {
        self.fileName = fileName
        self.magic = Data(magic.utf8)
        self.version = version
        self.purpose = Data(purpose.utf8)
        self.maxFileBytes = maxFileBytes
    }

    var header: Data {
        magic + Data([version])
    }

    public static let quickInsert = SealedFileFormat(
        fileName: AppIdentity.quickInsertFileName, magic: "PESTOQIS", version: 1, purpose: "pesto.quick-insert.v1",
        maxFileBytes: QuickInsertPolicy.maxFileBytes
    )

    public static let widgetSnapshot = SealedFileFormat(
        fileName: AppIdentity.widgetSnapshotFileName, magic: "PESTOWGT", version: 1,
        purpose: "pesto.widget-snapshot.v1", maxFileBytes: WidgetSnapshotPolicy.maxFileBytes
    )
}
