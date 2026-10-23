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
        for (folder, minimum) in [("App", 30), ("Features", 60)] {
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
}
