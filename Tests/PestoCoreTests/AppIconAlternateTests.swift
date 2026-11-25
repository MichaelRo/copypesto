// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The iPhone's theme icons")
struct AppIconAlternateTests {
    @Test("Basil is the primary icon and every other theme names an icon the app ships")
    func whenChoice_thenItsAlternateIcon() {
        #expect(AppIconChoice.basil.alternateIconName == nil)
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/Resources")
        for choice in AppIconChoice.allCases {
            #expect(AppIconChoice(alternateIconName: choice.alternateIconName) == choice)
            guard let name = choice.alternateIconName else { continue }
            let manifest = folder.appendingPathComponent("\(name).icon/icon.json")
            #expect(FileManager.default.fileExists(atPath: manifest.path), "\(name).icon")
        }
        #expect(AppIconChoice(alternateIconName: "Unknown") == .basil)
    }

    @Test("every icon is declared for every square platform, so the iPhone gets the layered icon")
    func whenIconManifestRead_thenSharedAcrossPlatforms() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/Resources")
        for name in ["Pesto", "PestoParmesan", "PestoPineNut", "PestoMortar"] {
            let data = try Data(contentsOf: folder.appendingPathComponent("\(name).icon/icon.json"))
            let manifest = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let platforms = try #require(manifest["supported-platforms"] as? [String: Any])
            #expect(platforms["squares"] as? String == "shared", "\(name)")
        }
    }
}
