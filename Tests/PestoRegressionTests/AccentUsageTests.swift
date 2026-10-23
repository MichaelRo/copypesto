// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Accent colour")
struct AccentUsageTests {
    @Test("views draw with the user's accent (@Environment pestoAccent), never Color.accentColor, which ignores .tint")
    func noSystemAccentInViews() throws {
        let allowed: Set = ["AccentColor.swift", "PestoAccentEnvironment.swift"]
        var offenders: [String] = []
        for (folder, minimum) in ["Features": 60, "Shared": 15, "App": 30] {
            let files = try SourceTree.swiftFiles(in: folder, minimum: minimum)
            for file in files where !allowed.contains(file.lastPathComponent) {
                for (number, line) in try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                    .enumerated()
                    where line.contains("Color.accentColor") || line.contains(".accentColor") && !line
                    .contains("accentColorHex")
                    || line.contains("controlAccentColor") || line.contains("Color(\"AccentColor\")")
                {
                    if !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                        offenders.append("\(file.lastPathComponent):\(number + 1)")
                    }
                }
            }
        }

        #expect(offenders.isEmpty, "use @Environment(\\.pestoAccent): \(offenders.joined(separator: ", "))")
    }

    @Test(
        "a text button is drawn in the accent through PestoLinkButtonStyle, because .buttonStyle(.link) is system blue"
    )
    func noSystemBlueLinks() throws {
        var offenders: [String] = []
        for (folder, minimum) in ["Features": 60, "Shared": 15, "App": 30] {
            for file in try SourceTree.swiftFiles(in: folder, minimum: minimum) {
                for (number, line) in try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                    .enumerated() where line.contains("buttonStyle(.link)")
                {
                    offenders.append("\(file.lastPathComponent):\(number + 1)")
                }
            }
        }

        #expect(offenders.isEmpty, "use .buttonStyle(.pestoLink): \(offenders.joined(separator: ", "))")
    }

    @Test("a filled button goes through PestoProminentButtonStyle, because the system styles print white on the accent")
    func noSystemProminentButtons() throws {
        var offenders: [String] = []
        for (folder, minimum) in ["Features": 60, "Shared": 15, "App": 30] {
            for file in try SourceTree.swiftFiles(in: folder, minimum: minimum) {
                for (number, line) in try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                    .enumerated() where line.contains(".borderedProminent") || line.contains(".glassProminent")
                {
                    offenders.append("\(file.lastPathComponent):\(number + 1)")
                }
            }
        }

        #expect(offenders.isEmpty, "use .buttonStyle(.pestoProminent): \(offenders.joined(separator: ", "))")
    }

    @Test("the tick slider fills its track with the accent, not the system blue")
    func tickSliderUsesTheAccent() throws {
        let file = try #require(
            try SourceTree.swiftFiles(in: "Shared", minimum: 15).first { $0.lastPathComponent == "TickSlider.swift" }
        )
        let source = try String(contentsOf: file, encoding: .utf8)

        #expect(source.contains("trackFillColor"))
    }

    @Test(
        "status text uses Color.statusWarning and Color.statusBad: the system orange and red fail 4.5:1 on light rows"
    )
    func noSystemStatusColorsOnText() throws {
        var offenders: [String] = []
        for (folder, minimum) in ["Features": 60, "Shared": 15, "App": 30] {
            for file in try SourceTree.swiftFiles(in: folder, minimum: minimum) {
                let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                for (number, line) in lines.enumerated()
                    where line.contains("Text(") && (line.contains(".foregroundStyle(.red)")
                        || line.contains(".foregroundStyle(.orange)"))
                {
                    offenders.append("\(file.lastPathComponent):\(number + 1)")
                }
            }
        }

        #expect(offenders.isEmpty, "use Color.statusBad or Color.statusWarning: \(offenders.joined(separator: ", "))")
    }
}
