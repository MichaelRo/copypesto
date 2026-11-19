// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// SwiftUI `Text("…")` localises itself; AppKit strings (alerts, menu items, window titles, accessibility labels) do
/// not, and stayed plain literals until `String(localized:)` was put round each. `makeItem` and `attempt` take a
/// `String.LocalizationValue`, so the compiler enforces those two.
@Suite("Localization routing")
struct LocalizationRoutingTests {
    private static let bare = try? NSRegularExpression(
        pattern: #"(?:messageText|informativeText|\.title)\s*=\s*"|addButton\(withTitle:\s*"|NSMenuItem\(title:\s*""#
            + #"|setAccessibilityLabel\(""#
    )

    @Test("the scan recognises a bare AppKit string and leaves a localised one alone")
    func scanRecognisesBareStrings() {
        func flagged(_ line: String) -> Bool {
            Self.bare?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        }
        #expect(flagged(#"alert.messageText = "Pesto can't"#))
        #expect(flagged(#"alert.addButton(withTitle: "Quit")"#))
        #expect(flagged(#"win.title = "Settings""#))
        #expect(flagged(#"panel.setAccessibilityLabel("Pinned clips")"#))
        #expect(!flagged(#"alert.messageText = String(localized: "Pesto can't")"#))
        #expect(!flagged(#"alert.addButton(withTitle: String(localized: "Quit"))"#))
    }

    @Test("no alert, window title or accessibility label in App or Features is a bare string")
    func noBareAppKitStrings() throws {
        var offenders: [String] = []
        for (folder, minimum) in [
            ("App", 30),
            ("Features", 60),
            ("Mobile", 3),
            ("MobileShare", 3),
            ("MobileAutoFill", 2),
            ("MobileWidget", 2),
            ("Widget", 10)
        ] {
            for file in try SourceTree.swiftFiles(in: folder, minimum: minimum) {
                let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                for (number, line) in lines.enumerated() {
                    if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                    if Self.bare?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                        offenders.append("\(file.lastPathComponent):\(number + 1)")
                    }
                }
            }
        }

        #expect(offenders.isEmpty, "wrap in String(localized:): \(offenders.joined(separator: ", "))")
    }

    @Test("all six app and extension targets include Localizable.xcstrings in Pesto.yml")
    func allTargetsIncludeLocalizableCatalog() throws {
        let project = try String(
            contentsOf: SourceTree.repositoryRoot.appendingPathComponent("Pesto.yml"), encoding: .utf8
        )
        let targets = ["Pesto", "PestoControls", "PestoMobile", "PestoShare", "PestoAutoFill", "PestoWidget"]
        for name in targets {
            let block = try targetBlock(named: name, in: project)
            #expect(
                block.contains("Sources/Resources/Localizable.xcstrings"),
                "\(name) is missing Sources/Resources/Localizable.xcstrings in Pesto.yml"
            )
        }
        for name in ["Pesto", "PestoMobile"] {
            let block = try targetBlock(named: name, in: project)
            #expect(
                block.contains("Sources/Resources/InfoPlist.xcstrings"),
                "\(name) is missing Sources/Resources/InfoPlist.xcstrings in Pesto.yml"
            )
            #expect(
                block.contains("Sources/Resources/AppShortcuts.xcstrings"),
                "\(name) is missing Sources/Resources/AppShortcuts.xcstrings in Pesto.yml"
            )
        }
    }

    @Test("InfoPlist.xcstrings and AppShortcuts.xcstrings parse as valid JSON string catalogs")
    func infoPlistAndAppShortcutsCatalogsAreValid() throws {
        let infoURL = SourceTree.sources.appendingPathComponent("Resources/InfoPlist.xcstrings")
        let infoStrings = try parseStringCatalog(at: infoURL)
        for key in [
            "CFBundleDisplayName",
            "CFBundleName",
            "NSAccessibilityUsageDescription",
            "NSPhotoLibraryAddUsageDescription",
            "NSFaceIDUsageDescription",
            "NSHumanReadableCopyright"
        ] {
            #expect(hasEnglishTranslation(infoStrings, key: key), "InfoPlist.xcstrings missing en entry for \(key)")
        }

        let shortcutsURL = SourceTree.sources.appendingPathComponent("Resources/AppShortcuts.xcstrings")
        let shortcutStrings = try parseStringCatalog(at: shortcutsURL)
        for key in [
            "Add to ${applicationName}",
            "Save to ${applicationName}",
            "Add my clipboard to ${applicationName}",
            "Add clipboard to ${applicationName}",
            "Search ${applicationName}",
            "Add to Pesto",
            "Add Clipboard to Pesto",
            "Search Pesto"
        ] {
            #expect(
                hasEnglishTranslation(shortcutStrings, key: key),
                "AppShortcuts.xcstrings missing en entry for \(key)"
            )
        }
    }

    @Test("all three string catalogs translate every key into all twelve target locales plus English")
    func allCatalogsCoverAllSupportedLocales() throws {
        let locales = ["en", "es", "fr", "de", "ja", "zh-Hans", "pt-BR", "he", "ru", "uk", "ko", "it", "cs"]
        for file in ["InfoPlist.xcstrings", "AppShortcuts.xcstrings", "Localizable.xcstrings"] {
            let url = SourceTree.sources.appendingPathComponent("Resources/\(file)")
            let strings = try parseStringCatalog(at: url)
            #expect(!strings.isEmpty, "\(file) should not be empty")
            for (key, rawEntry) in strings {
                let entry = try #require(rawEntry as? [String: Any], "\(file)[\(key)]")
                let localizations = try #require(entry["localizations"] as? [String: Any], "\(file)[\(key)]")
                for locale in locales {
                    #expect(
                        hasTranslatedContent(localizations[locale]),
                        "\(file) missing translated \(locale) entry for \(key)"
                    )
                }
            }
        }
    }

    private func targetBlock(named name: String, in project: String) throws -> String {
        let marker = "\n  \(name):\n"
        let start = try #require(project.range(of: marker), "\(name) target in Pesto.yml").upperBound
        let rest = project[start...]
        let end = rest.range(of: "\n  [A-Za-z]+:\n", options: .regularExpression)?.lowerBound
            ?? rest.range(of: "\nschemes:\n")?.lowerBound
            ?? rest.endIndex
        return String(rest[..<end])
    }

    private func parseStringCatalog(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let root = try #require(json, "\(url.lastPathComponent) is a JSON object")
        #expect(root["sourceLanguage"] as? String == "en")
        #expect(root["version"] as? String == "1.0")
        return try #require(root["strings"] as? [String: Any], "\(url.lastPathComponent) has a strings dictionary")
    }

    private func hasEnglishTranslation(_ strings: [String: Any], key: String) -> Bool {
        guard let entry = strings[key] as? [String: Any],
              let localizations = entry["localizations"] as? [String: Any],
              let en = localizations["en"] as? [String: Any],
              let unit = en["stringUnit"] as? [String: Any],
              let value = unit["value"] as? String else { return false }
        return !value.isEmpty
    }

    private func hasTranslatedContent(_ rawLocale: Any?) -> Bool {
        guard let locale = rawLocale as? [String: Any] else { return false }
        if let unit = locale["stringUnit"] as? [String: Any],
           let value = unit["value"] as? String
        {
            return !value.isEmpty
        }
        if let variations = locale["variations"] as? [String: Any],
           let plural = variations["plural"] as? [String: Any],
           !plural.isEmpty
        {
            return plural.values.allSatisfy { rawForm in
                guard let form = rawForm as? [String: Any],
                      let unit = form["stringUnit"] as? [String: Any],
                      let value = unit["value"] as? String else { return false }
                return !value.isEmpty
            }
        }
        return false
    }
}
