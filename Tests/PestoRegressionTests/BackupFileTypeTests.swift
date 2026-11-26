// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The .pestobackup file type")
struct BackupFileTypeTests {
    private func info(at relativePath: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent(relativePath))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test("the identifier is built from the app's identity")
    func identifier_followsTheBundleID() {
        #expect(BackupFileType.identifier == "\(AppIdentity.bundleID).backup")
        #expect(BackupFileType.fileExtension == "pestobackup")
    }

    @Test("both apps export the type as data with the pestobackup extension", arguments: [
        "Sources/Resources/Info.plist",
        "Sources/Resources/PestoMobile-Info.plist"
    ])
    func infoPlist_exportsTheType(plistPath: String) throws {
        let declarations = try #require(info(at: plistPath)["UTExportedTypeDeclarations"] as? [[String: Any]])
        let declaration = try #require(declarations.first {
            $0["UTTypeIdentifier"] as? String == BackupFileType.identifier
        })
        #expect(declaration["UTTypeConformsTo"] as? [String] == ["public.data"])
        let tags = try #require(declaration["UTTypeTagSpecification"] as? [String: Any])
        #expect(tags["public.filename-extension"] as? [String] == [BackupFileType.fileExtension])
    }
}
