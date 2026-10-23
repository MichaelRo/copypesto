// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Quiet text")
struct QuietTextScanTests {
    @Test("no view draws with the system .secondary or .yellow: both fail 4.5:1 on a light ground (A-15)")
    func noSecondaryOrYellow() throws {
        let pattern = try NSRegularExpression(pattern: #"foregroundStyle\(\.(secondary|yellow)\)"#)
        var offenders: [String] = []
        for file in try SourceTree.everySwiftFile() where file.path.contains("/Sources/Features/")
            || file.path.contains("/Sources/App/") || file.path.contains("/Sources/Shared/")
        {
            for (number, line) in try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                .enumerated()
                where pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
            {
                offenders.append("\(SourceTree.relativePath(file)):\(number + 1)")
            }
        }

        #expect(offenders.isEmpty, "use .pestoQuiet() or Color.statusWarning: \(offenders.joined(separator: ", "))")
    }

    @Test("settings, collections and shared components draw text with no system .secondary or .tertiary colour")
    func noFaintSystemColourInSettingsText() throws {
        let pattern =
            try NSRegularExpression(pattern: #"foregroundStyle\(.*(Color\.(secondary|tertiary)|\.tertiary)\)"#)
        var offenders: [String] = []
        // Keycap's compact cap on a card is faint on purpose, and says so; its audited text uses `solid`.
        let faintOnPurpose = ["Sources/Shared/Components/Keycap.swift"]
        for file in try SourceTree.everySwiftFile() {
            let path = SourceTree.relativePath(file)
            guard path.hasPrefix("Sources/Features/Settings/") || path.hasPrefix("Sources/Features/Collections/")
                || path.hasPrefix("Sources/Shared/Components/"), !faintOnPurpose.contains(path) else { continue }
            for (number, line) in try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                .enumerated()
                where pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
            {
                offenders.append("\(path):\(number + 1)")
            }
        }

        #expect(offenders.isEmpty, "use .pestoQuiet() or AdaptiveContrast.quiet: \(offenders.joined(separator: ", "))")
    }
}
