// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Motion family")
struct MotionFamilyTests {
    private static let curves = "easeInOut|easeIn|easeOut|linear|spring|snappy|smooth|bouncy|interactiveSpring"
        + "|interpolatingSpring"

    /// Where a curve may be defined: the family and the pictures' settle springs.
    private static let definitionFiles: Set<String> = [
        "Shared/Extensions/Motion.swift",
        "Shared/Components/SettleOnAppear.swift"
    ]

    private func path(_ file: URL) -> String {
        file.path.replacingOccurrences(of: SourceTree.sources.path + "/", with: "")
    }

    @Test("a view animates with a name from Motion.swift, not a curve of its own")
    func whenAViewAnimates_thenTheCurveIsOneOfTheFamily() throws {
        let literal = try NSRegularExpression(pattern: #"Motion\.animation\(\s*\.(?:"# + Self.curves + #")\b"#)
        var offenders: [String] = []
        for file in try SourceTree.everySwiftFile() {
            try autoreleasepool {
                let text = try String(contentsOf: file, encoding: .utf8)
                guard text.contains("Motion.animation(") else { return }
                let found = literal.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
                if found > 0 { offenders.append("\(path(file)): \(found)") }
            }
        }

        #expect(offenders.isEmpty, "curves outside the motion family: \(offenders.sorted().joined(separator: "; "))")
    }

    @Test("a named curve is defined only beside the family")
    func whenACurveIsNamed_thenItLivesInTheMotionFiles() throws {
        let definition = try NSRegularExpression(pattern: #"\bAnimation\s*\.\s*(?:"# + Self.curves + #")\b"#)
        var offenders: [String] = []
        for file in try SourceTree.everySwiftFile() where !Self.definitionFiles.contains(path(file)) {
            try autoreleasepool {
                let text = try String(contentsOf: file, encoding: .utf8)
                guard text.contains("Animation") else { return }
                if definition.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                    offenders.append(path(file))
                }
            }
        }

        #expect(
            offenders.isEmpty,
            "curves defined outside the motion files: \(offenders.sorted().joined(separator: ", "))"
        )
    }
}
