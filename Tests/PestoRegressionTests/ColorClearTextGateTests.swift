// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Clear-text previews")
struct ColorClearTextGateTests {
    @Test("storage code never decides on its own that a colour's preview stays in the clear (R-01, ADR 0002)")
    func onlyColorPreviewPolicyDecides() throws {
        let pattern = try NSRegularExpression(pattern: #"(?:!=|==)\s*\.color\b"#)
        var offenders: [String] = []
        for file in try SourceTree.everySwiftFile() where file.path.contains("/Sources/Core/Storage/") {
            for (number, line) in try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                .enumerated()
                where !line.contains("ColorPreviewPolicy")
                && pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
            {
                offenders.append("\(file.lastPathComponent):\(number + 1)")
            }
        }

        #expect(offenders.isEmpty, "ask ColorPreviewPolicy instead: \(offenders.joined(separator: ", "))")
    }
}
