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

    @Test("Pesto.yml gives the app, its controls, the share extension and the CLI the identifiers the code uses")
    func projectMatchesAppIdentity() throws {
        let project = try String(contentsOf: root.appendingPathComponent("Pesto.yml"), encoding: .utf8)
        for id in [
            AppIdentity.bundleID, AppIdentity.controlsBundleID, AppIdentity.cliBundleID, AppIdentity.shareBundleID
        ] {
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
        #expect(AppIdentity.inboxKeyAccount.hasPrefix(AppIdentity.bundleID))
        #expect(AppIdentity.shareBundleID == "net.copypesto.pesto.share")
        #expect(AppIdentity.autofillBundleID == "net.copypesto.pesto.autofill")
        #expect(AppIdentity.quickInsertKeyAccount == "net.copypesto.pesto.quickInsertKey")
        #expect(AppIdentity.quickInsertKeychainGroupName == "net.copypesto.pesto.quick-insert")
        #expect(AppIdentity
            .quickInsertKeychainGroup(prefix: "ABCDE12345.") == "ABCDE12345.net.copypesto.pesto.quick-insert")
        #expect(AppIdentity.quickInsertFileName != AppIdentity.inboxPublicKeyFileName)
    }

    @Test("the app group the iOS app and its share extension name is the bundle ID's, in both entitlements files")
    func appGroupMatchesTheEntitlements() throws {
        #expect(AppIdentity.appGroupID == "group.net.copypesto.pesto")
        for path in ["Sources/Resources/PestoMobile.entitlements", "Sources/MobileShare/PestoShare.entitlements"] {
            let data = try Data(contentsOf: root.appendingPathComponent(path))
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            let groups = plist?["com.apple.security.application-groups"] as? [String]
            #expect(groups == [AppIdentity.appGroupID], "\(path) names \(groups ?? [])")
        }
    }
}
