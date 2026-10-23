// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Selectable tiles")
struct SelectableTileScanTests {
    @Test(
        "a tile that marks itself selected goes through selectableTile, which also gives it a name and a press action"
    )
    func selectedTraitOnlyThroughSelectableTile() throws {
        var offenders: [String] = []
        // The modifier itself, and the sidebar's rows: plain buttons that keep their content, so they keep their press
        // action and are audited with the window.
        let exempt = ["Sources/Shared/Components/SelectableTile.swift", "Sources/Features/Settings/SettingsView.swift"]
        for file in try SourceTree.everySwiftFile() {
            let path = SourceTree.relativePath(file)
            guard path.hasPrefix("Sources/Features/Settings/") || path.hasPrefix("Sources/Features/Collections/")
                || path.hasPrefix("Sources/Shared/Components/"), !exempt.contains(path) else { continue }
            for (number, line) in try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                .enumerated() where line.contains("accessibilityAddTraits") && line.contains(".isSelected")
            {
                offenders.append("\(path):\(number + 1)")
            }
        }

        #expect(
            offenders.isEmpty,
            "use .selectableTile(_:isSelected:perform:): \(offenders.joined(separator: ", "))"
        )
    }
}
