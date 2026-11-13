// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Motion family")
struct MotionFamilyTests {
    private static let curves = "easeInOut|easeIn|easeOut|linear|spring|snappy|smooth|bouncy|interactiveSpring"
        + "|interpolatingSpring"

    /// Files that still hand `Motion.animation` a curve of their own, and how many. A count may only go down: move the
    /// call to one of the names in `Motion.swift` and lower it here, and remove the entry at zero.
    private static let literalAllowlist: [String: Int] = [
        "Features/Settings/ThemePicker.swift": 1,
        "Features/Settings/AppearancePreviews.swift": 1,
        "Features/CommandBar/CommandBarView.swift": 3,
        "Features/AI/AIResultPanelController.swift": 1,
        "Features/Overlay/BiometricLockOverlay.swift": 3,
        "Features/Overlay/StackHUDWindowController.swift": 1,
        "Features/Overlay/ToastView.swift": 1,
        "Features/Overlay/ShelfBackground.swift": 1,
        "Features/Grid/GridView+SelectionBar.swift": 1,
        "Features/Grid/GridView+Filtering.swift": 1,
        "Features/Grid/GridView.swift": 2,
        "Shared/Components/PreviewPicker.swift": 1
    ]

    /// Where a curve may be defined: the family, the pictures' settle springs, and the shelf's switch ease until it
    /// joins the family.
    private static let definitionFiles: Set<String> = [
        "Shared/Extensions/Motion.swift",
        "Shared/Components/SettleOnAppear.swift",
        "Features/Grid/ShelfMotion.swift"
    ]

    private func path(_ file: URL) -> String {
        file.path.replacingOccurrences(of: SourceTree.sources.path + "/", with: "")
    }

    @Test("a view animates with a name from Motion.swift, not a curve of its own")
    func whenAViewAnimates_thenTheCurveIsOneOfTheFamily() throws {
        let literal = try NSRegularExpression(pattern: #"Motion\.animation\(\s*\.(?:"# + Self.curves + #")\b"#)
        var offenders: [String] = []
        var scanned: Set<String> = []
        for file in try SourceTree.everySwiftFile() {
            let relative = path(file)
            scanned.insert(relative)
            let text = try String(contentsOf: file, encoding: .utf8)
            let found = literal.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            let allowed = Self.literalAllowlist[relative] ?? 0
            if found != allowed { offenders.append("\(relative): \(found) found, \(allowed) allowed") }
        }
        let stale = Self.literalAllowlist.keys.filter { !scanned.contains($0) }.sorted()

        #expect(stale.isEmpty, "the allowlist names files that do not exist: \(stale.joined(separator: ", "))")
        #expect(offenders.isEmpty, "curves outside the motion family: \(offenders.sorted().joined(separator: "; "))")
    }

    @Test("a named curve is defined only beside the family")
    func whenACurveIsNamed_thenItLivesInTheMotionFiles() throws {
        let definition = try NSRegularExpression(pattern: #"\bAnimation\s*\.\s*(?:"# + Self.curves + #")\b"#)
        var offenders: [String] = []
        for file in try SourceTree.everySwiftFile() where !Self.definitionFiles.contains(path(file)) {
            let text = try String(contentsOf: file, encoding: .utf8)
            if definition.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                offenders.append(path(file))
            }
        }

        #expect(
            offenders.isEmpty,
            "curves defined outside the motion files: \(offenders.sorted().joined(separator: ", "))"
        )
    }
}
