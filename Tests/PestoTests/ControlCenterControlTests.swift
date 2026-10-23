// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import Testing
@testable import Pesto

@Suite("Control Center control")
struct ControlCenterControlTests {
    @Test("the app bundle ships the controls extension")
    func whenAppBuilt_thenExtensionEmbedded() throws {
        let plugIns = try #require(Bundle.main.builtInPlugInsURL)
        let extensions = try FileManager.default.contentsOfDirectory(at: plugIns, includingPropertiesForKeys: nil)

        #expect(extensions.contains { $0.lastPathComponent == "PestoControls.appex" }, "\(extensions)")
    }

    @Test("the extension declares itself as a WidgetKit extension")
    func whenInfoRead_thenWidgetKitExtensionPoint() throws {
        let plugIns = try #require(Bundle.main.builtInPlugInsURL)
        let bundle = try #require(Bundle(url: plugIns.appendingPathComponent("PestoControls.appex")))
        let info = try #require(bundle.infoDictionary?["NSExtension"] as? [String: Any])

        #expect(info["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension")
        #expect(bundle.bundleIdentifier == "net.copypesto.pesto.controls")
    }

    @Test("the control opens the shelf through a URL the app already handles")
    func whenControlPressed_thenOpenActionExists() {
        #expect(AutomationAction(host: "open") == .open)
    }
}
