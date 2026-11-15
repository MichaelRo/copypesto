// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Entitlements and purpose strings")
struct EntitlementsTests {
    private func plist(_ relativePath: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent(relativePath))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test("the release entitlements do not ask for Apple Events or a sandbox-only network entitlement")
    func releaseEntitlements_areMinimal() throws {
        let entitlements = try plist("Sources/Resources/Pesto.entitlements")

        #expect(entitlements["com.apple.security.automation.apple-events"] == nil)
        #expect(entitlements["com.apple.security.network.client"] == nil)
    }

    @Test("v1 ships without iCloud: no entitlement, so no provisioning profile is needed to sign it")
    func releaseEntitlements_haveNoICloud() throws {
        let entitlements = try plist("Sources/Resources/Pesto.entitlements")

        #expect(!entitlements.keys.contains { $0.contains("icloud") })
    }

    @Test("the sync entitlements are only the two a Developer ID profile grants, and the default ones stay empty")
    func syncEntitlements_areTheTwoAProfileGrants() throws {
        let sync = try plist("Sources/Resources/PestoSync.entitlements")

        #expect(Set(sync.keys) == ["com.apple.application-identifier", "com.apple.developer.team-identifier"])
        #expect(try plist("Sources/Resources/Pesto.entitlements").isEmpty, "a build without the profile claims nothing")
    }

    @Test("each iOS entitlements file claims exactly its keys, and the Mac files name none of them")
    func iOSEntitlements_arePinned() throws {
        let group = "com.apple.security.application-groups"
        let keychain = "keychain-access-groups"
        let autofill = "com.apple.developer.authentication-services.autofill-credential-provider"
        #expect(try Set(plist("Sources/Resources/PestoMobile.entitlements").keys) == [group, keychain])
        #expect(try Set(plist("Sources/MobileShare/PestoShare.entitlements").keys) == [group])
        #expect(try Set(plist("Sources/MobileAutoFill/PestoAutoFill.entitlements").keys) == [group, keychain, autofill])
        #expect(try plist("Sources/MobileAutoFill/PestoAutoFill.entitlements")[autofill] as? Bool == true)
        for path in ["Sources/Resources/Pesto.entitlements", "Sources/Resources/PestoSync.entitlements"] {
            for key in [group, keychain, autofill] {
                #expect(try plist(path)[key] == nil, "\(path) names \(key)")
            }
        }
    }

    @Test("the app's own Keychain group comes first, so only the quick-insert key is in the group AutoFill shares")
    func iOSKeychainGroups_keepTheAppsItemsItsOwn() throws {
        let prefix = "$(AppIdentifierPrefix)"
        let app = try plist("Sources/Resources/PestoMobile.entitlements")["keychain-access-groups"] as? [String]
        let autoFill = try plist("Sources/MobileAutoFill/PestoAutoFill.entitlements")["keychain-access-groups"]
            as? [String]
        #expect(app == [prefix + AppIdentity.bundleID, AppIdentity.quickInsertKeychainGroup(prefix: prefix)])
        #expect(autoFill == [AppIdentity.quickInsertKeychainGroup(prefix: prefix)])
        for path in ["Sources/Resources/PestoMobile-Info.plist", "Sources/MobileAutoFill/Info.plist"] {
            #expect(try plist(path)[AppIdentity.appIdentifierPrefixInfoKey] as? String == prefix, "\(path)")
        }
    }

    @Test("the AutoFill extension offers text insertion and nothing else: no passwords, passkeys or codes")
    func autoFillExtension_providesTextInsertionOnly() throws {
        let info = try plist("Sources/MobileAutoFill/Info.plist")
        let extensionInfo = try #require(info["NSExtension"] as? [String: Any])
        #expect(
            extensionInfo["NSExtensionPointIdentifier"] as? String
                == "com.apple.authentication-services-credential-provider-ui"
        )
        let attributes = try #require(extensionInfo["NSExtensionAttributes"] as? [String: Any])
        #expect(Set(attributes.keys) == ["ASCredentialProviderExtensionCapabilities"])
        let capabilities = try #require(attributes["ASCredentialProviderExtensionCapabilities"] as? [String: Any])
        #expect(Set(capabilities.keys) == ["ProvidesTextToInsert"])
        #expect(capabilities["ProvidesTextToInsert"] as? Bool == true)
    }

    @Test("the share extension is offered only for text, one link and one picture, never for everything")
    func shareExtension_activatesForTextLinksAndPictures() throws {
        let info = try plist("Sources/MobileShare/Info.plist")
        let extensionInfo = try #require(info["NSExtension"] as? [String: Any])
        #expect(extensionInfo["NSExtensionPointIdentifier"] as? String == "com.apple.share-services")
        let attributes = try #require(extensionInfo["NSExtensionAttributes"] as? [String: Any])
        let rule = try #require(attributes["NSExtensionActivationRule"] as? [String: Any])
        #expect(Set(rule.keys) == [
            "NSExtensionActivationSupportsText", "NSExtensionActivationSupportsWebURLWithMaxCount",
            "NSExtensionActivationSupportsImageWithMaxCount"
        ])
        #expect(rule["NSExtensionActivationSupportsWebURLWithMaxCount"] as? Int == 1)
        #expect(rule["NSExtensionActivationSupportsImageWithMaxCount"] as? Int == 1)
    }

    @Test("Info.plist has no Apple Events purpose string, since nothing sends Apple Events")
    func infoPlist_hasNoAppleEventsPurpose() throws {
        let info = try plist("Sources/Resources/Info.plist")

        #expect(info["NSAppleEventsUsageDescription"] == nil)
    }

    @Test("the app launches with the large-block cache of malloc off, which returned 110 MB after long copies")
    func infoPlist_turnsOffTheLargeBlockCache() throws {
        let info = try plist("Sources/Resources/Info.plist")
        let environment = try #require(info["LSEnvironment"] as? [String: String])

        // Undocumented libmalloc setting, measured with `make bench-latency memory`: the footprint after 200 long
        // copies
        // and 50 screenshots was 215 MB without it and 105 MB with it.
        #expect(environment["MallocLargeCache"] == "0")
    }
}
