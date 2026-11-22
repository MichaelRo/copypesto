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

    @Test("the Mac widget's entitlements are only for the build with both profiles; every other build claims none")
    func macWidgetEntitlements_areOnlyInTheProfileBuild() throws {
        let group = "com.apple.security.application-groups"
        let keychain = "keychain-access-groups"
        let sandbox = "com.apple.security.app-sandbox"
        let identifier = "com.apple.application-identifier"
        let team = "com.apple.developer.team-identifier"
        let app = try plist("Sources/Resources/PestoSyncWidget.entitlements")
        let controls = try plist("Sources/Controls/PestoControlsWidget.entitlements")
        let prefix = "$(DEVELOPMENT_TEAM)."

        #expect(Set(app.keys) == [identifier, team, group, keychain])
        #expect(app[identifier] as? String == prefix + AppIdentity.bundleID)
        #expect(app[group] as? [String] == [AppIdentity.appGroupID])
        #expect(app[keychain] as? [String] == [
            prefix + AppIdentity.bundleID,
            prefix + AppIdentity.widgetKeychainGroupName
        ])
        #expect(Set(controls.keys) == [sandbox, identifier, team, group, keychain])
        #expect(controls[sandbox] as? Bool == true)
        #expect(controls[identifier] as? String == prefix + AppIdentity.controlsBundleID)
        #expect(controls[group] as? [String] == [AppIdentity.appGroupID])
        #expect(controls[keychain] as? [String] == [prefix + AppIdentity.widgetKeychainGroupName])
        let development = try plist("Sources/Controls/PestoControls.entitlements")
        #expect(Set(development.keys) == [sandbox], "a build without the profiles claims only the sandbox")
        #expect(try plist("Sources/Resources/PestoSync.entitlements")[group] == nil)
    }

    @Test("each iOS entitlements file claims exactly its keys, and the Mac files name none of them")
    func iOSEntitlements_arePinned() throws {
        let group = "com.apple.security.application-groups"
        let keychain = "keychain-access-groups"
        let autofill = "com.apple.developer.authentication-services.autofill-credential-provider"
        #expect(try Set(plist("Sources/Resources/PestoMobile.entitlements").keys) == [group, keychain, autofill])
        #expect(try Set(plist("Sources/MobileShare/PestoShare.entitlements").keys) == [group])
        #expect(try Set(plist("Sources/MobileAutoFill/PestoAutoFill.entitlements").keys) == [group, keychain, autofill])
        #expect(try plist("Sources/MobileAutoFill/PestoAutoFill.entitlements")[autofill] as? Bool == true)
        #expect(try Set(plist("Sources/MobileKeyboard/PestoKeyboard.entitlements").keys) == [group, keychain])
        #expect(try Set(plist("Sources/MobileWidget/PestoWidget.entitlements").keys) == [group, keychain])
        for path in ["Sources/Resources/Pesto.entitlements", "Sources/Resources/PestoSync.entitlements"] {
            for key in [group, keychain, autofill] {
                #expect(try plist(path)[key] == nil, "\(path) names \(key)")
            }
        }
    }

    @Test("the app's own Keychain group comes first; AutoFill, the keyboard and the widget hold only their key's group")
    func iOSKeychainGroups_keepTheAppsItemsItsOwn() throws {
        let prefix = "$(AppIdentifierPrefix)"
        let app = try plist("Sources/Resources/PestoMobile.entitlements")["keychain-access-groups"] as? [String]
        let autoFill = try plist("Sources/MobileAutoFill/PestoAutoFill.entitlements")["keychain-access-groups"]
            as? [String]
        let keyboard = try plist("Sources/MobileKeyboard/PestoKeyboard.entitlements")["keychain-access-groups"]
            as? [String]
        let widget = try plist("Sources/MobileWidget/PestoWidget.entitlements")["keychain-access-groups"] as? [String]
        #expect(app == [
            prefix + AppIdentity.bundleID, AppIdentity.quickInsertKeychainGroup(prefix: prefix),
            AppIdentity.widgetKeychainGroup(prefix: prefix)
        ])
        #expect(autoFill == [AppIdentity.quickInsertKeychainGroup(prefix: prefix)])
        #expect(keyboard == [AppIdentity.quickInsertKeychainGroup(prefix: prefix)])
        #expect(widget == [AppIdentity.widgetKeychainGroup(prefix: prefix)])
        for path in [
            "Sources/Resources/PestoMobile-Info.plist", "Sources/MobileAutoFill/Info.plist",
            "Sources/MobileKeyboard/Info.plist", "Sources/MobileWidget/Info.plist"
        ] {
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
        #expect(
            Set(attributes.keys)
                == ["ASCredentialProviderExtensionCapabilities", "ASCredentialProviderExtensionShowsConfigurationUI"]
        )
        #expect(attributes["ASCredentialProviderExtensionShowsConfigurationUI"] as? Bool == true)
        let capabilities = try #require(attributes["ASCredentialProviderExtensionCapabilities"] as? [String: Any])
        #expect(Set(capabilities.keys) == ["ProvidesPasswords", "ProvidesTextToInsert"])
        #expect(capabilities["ProvidesPasswords"] as? Bool == true)
        #expect(capabilities["ProvidesTextToInsert"] as? Bool == true)
    }

    @Test("the keyboard is a keyboard extension that asks for Full Access and can be switched away from")
    func keyboardExtension_isAKeyboardThatAsksForFullAccess() throws {
        let info = try plist("Sources/MobileKeyboard/Info.plist")
        let extensionInfo = try #require(info["NSExtension"] as? [String: Any])
        #expect(extensionInfo["NSExtensionPointIdentifier"] as? String == "com.apple.keyboard-service")
        #expect(
            extensionInfo["NSExtensionPrincipalClass"] as? String == "$(PRODUCT_MODULE_NAME).KeyboardViewController"
        )
        let attributes = try #require(extensionInfo["NSExtensionAttributes"] as? [String: Any])
        #expect(attributes["RequestsOpenAccess"] as? Bool == true)
        #expect(attributes["IsASCIICapable"] as? Bool == false)
    }

    @Test("the keyboard reads no pasteboard, opens no connection and never touches the store or the history key")
    func keyboardSources_reachOnlyTheQuickInsertSet() throws {
        let forbidden = [
            "URLSession", "NWConnection", "ModelContainer", "ModelContext", "StorageService",
            "blobKeyAccount", "inboxKeyAccount", "InboxKeyStore", "BackupKeyStore", "SyncKeyStore",
            "KeychainDeviceKeyStore", "AppKeychainGroup"
        ]
        let pasteboardReads = [
            "UIPasteboard.general.string", "UIPasteboard.general.image", "UIPasteboard.general.url",
            "UIPasteboard.general.items", "UIPasteboard.general.itemProviders",
            "UIPasteboard.general.hasStrings", "UIPasteboard.general.hasImages", "UIPasteboard.general.hasURLs",
            "UIPasteboard.general.pasteboardTypes", "UIPasteboard.general.data(", "UIPasteboard.general.value("
        ]
        for file in try SourceTree.swiftFiles(in: "MobileKeyboard", minimum: 4) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for name in forbidden + pasteboardReads {
                #expect(!text.contains(name), "\(file.lastPathComponent) names \(name)")
            }
        }
    }

    @Test("the widget is a WidgetKit extension, and the app opens pesto:// links, the widget's among them")
    func widgetExtension_isWidgetKitAndTheAppTakesTheScheme() throws {
        let info = try plist("Sources/MobileWidget/Info.plist")
        let extensionInfo = try #require(info["NSExtension"] as? [String: Any])
        #expect(Set(extensionInfo.keys) == ["NSExtensionPointIdentifier"])
        #expect(extensionInfo["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension")
        let types =
            try #require(plist("Sources/Resources/PestoMobile-Info.plist")["CFBundleURLTypes"] as? [[String: Any]])
        #expect(types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] } == [AppIdentity.urlScheme])
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
