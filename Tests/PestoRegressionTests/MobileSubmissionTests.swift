// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// What the App Store checks before it looks at the app: a privacy manifest in every iOS bundle that names the
/// required-reason APIs Pesto's code calls, and a Face ID purpose string (without it iOS ends the app the moment the
/// History Lock asks for Face ID; the simulator does not enforce it).
@Suite("The iOS app is ready to upload")
struct MobileSubmissionTests {
    static let bundleFolders = [
        "Sources/Mobile",
        "Sources/MobileShare",
        "Sources/MobileAutoFill",
        "Sources/MobileKeyboard",
        "Sources/MobileWidget"
    ]

    private func manifest(in folder: String) throws -> [String: Any] {
        let url = SourceTree.repositoryRoot.appendingPathComponent(folder)
            .appendingPathComponent("PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: Any], "\(folder)/PrivacyInfo.xcprivacy is a dictionary")
    }

    @Test("each iOS bundle says it does not track and collects nothing", arguments: bundleFolders)
    func noTrackingNoCollection(folder: String) throws {
        let plist = try manifest(in: folder)
        #expect(plist["NSPrivacyTracking"] as? Bool == false)
        #expect((plist["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
        #expect((plist["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
    }

    @Test("each iOS bundle names the reason for preferences and file dates", arguments: bundleFolders)
    func requiredReasons(folder: String) throws {
        let plist = try manifest(in: folder)
        let entries = try #require(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let reasons = Dictionary(uniqueKeysWithValues: entries.compactMap { entry -> (String, [String])? in
            guard let type = entry["NSPrivacyAccessedAPIType"] as? String,
                  let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] else { return nil }
            return (type, reasons)
        })
        #expect(reasons["NSPrivacyAccessedAPICategoryUserDefaults"] == ["CA92.1"])
        #expect(reasons["NSPrivacyAccessedAPICategoryFileTimestamp"]?.contains("C617.1") == true)
    }

    @Test("the app says why it asks for Face ID")
    func faceIDPurpose() throws {
        let spec = try String(
            contentsOf: SourceTree.repositoryRoot.appendingPathComponent("Pesto.yml"), encoding: .utf8
        )
        let mobile = try #require(spec.range(of: "\n  PestoMobile:\n"), "the PestoMobile target")
        let rest = spec[mobile.upperBound...]
        let target = rest.range(of: "\n  [A-Za-z]+:\n", options: .regularExpression)
            .map { rest[..<$0.lowerBound] } ?? rest
        #expect(target.contains("INFOPLIST_KEY_NSFaceIDUsageDescription:"))
    }
}
