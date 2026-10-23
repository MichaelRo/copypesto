// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("App identity")
struct AppIdentityTests {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test("Pesto.yml gives the app, its controls and the CLI the identifiers the code uses")
    func projectMatchesAppIdentity() throws {
        let project = try String(contentsOf: root.appendingPathComponent("Pesto.yml"), encoding: .utf8)
        for id in [AppIdentity.bundleID, AppIdentity.controlsBundleID, AppIdentity.cliBundleID] {
            #expect(project.contains("PRODUCT_BUNDLE_IDENTIFIER: \(id)\n"), "\(id) missing from Pesto.yml")
        }
    }

    @Test("the old identifier survives only where it names something that was left behind")
    func legacyIdentifierIsNotUsedForCurrentData() throws {
        let sources = root.appendingPathComponent("Sources")
        let allowed: Set = [
            "Core/Runtime/AppIdentity.swift", "Core/AI/LegacyAIKeyCleanup.swift",
            "Core/Runtime/AppDefaults.swift", "Core/Runtime/AppPaths.swift",
            "Core/Runtime/RuntimeConfiguration.swift", "Core/Storage/BlobEncryption.swift",
            "Core/Storage/ContentHash.swift"
        ]
        var offenders: [String] = []
        let files = try SourceTree.everySwiftFile()
        for file in files {
            let relative = file.path.replacingOccurrences(of: sources.path + "/", with: "")
            guard !allowed.contains(relative) else { continue }
            if try String(contentsOf: file, encoding: .utf8).contains("\"io.pesto.app") { offenders.append(relative) }
        }
        #expect(offenders.isEmpty, "old bundle ID used as a literal in: \(offenders.joined(separator: ", "))")
    }

    @Test("derived identifiers all start from the bundle ID")
    func derivedIdentifiersShareThePrefix() {
        #expect(AppIdentity.blobKeyAccount.hasPrefix(AppIdentity.bundleID))
        #expect(AppIdentity.deviceIDAccount.hasPrefix(AppIdentity.bundleID))
        #expect(AppIdentity.controlsBundleID == "net.copypesto.pesto.controls")
        #expect(AppIdentity.legacyBlobKeyAccount == "io.pesto.app.blobKey")
    }
}
