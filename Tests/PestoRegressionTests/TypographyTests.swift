// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Typography")
struct TypographyTests {
    @Test("no view sets a fixed font size below 10 pt; text styles scale and stay legible")
    func noTinyFixedFontSizes() throws {
        let pattern = try NSRegularExpression(pattern: #"\.system\(size: [0-9](?:\.[0-9])?[,)]"#)
        var offenders: [String] = []
        let files = try SourceTree.everySwiftFile()
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            if pattern.firstMatch(in: text, range: range) != nil { offenders.append(file.lastPathComponent) }
        }

        #expect(offenders.isEmpty, "fixed sub-10pt sizes in: \(offenders.joined(separator: ", "))")
    }

    /// 97 uses of `.font(.system(size:))` ignored Settings > Accessibility > Display >
    /// Text size. Text-bearing ones were converted to `.scaledFont(...)` (`ScaledFont.swift`), which
    /// wraps `@ScaledMetric`, capped for text inside a fixed-size card or a fixed-size AppKit panel.
    /// What remains is decorative: `Image(systemName:)` icons, and a chosen emoji standing in for one
    /// (`Text(symbol)`/`Text(emojiText)`/`Text(emoji)`) — icons don't need to track the reading text
    /// size. This test locks the allowlist by file and count, so a newly added fixed-size font
    /// must be justified (added to the list, if it really is decorative) or fixed (converted to
    /// `.scaledFont`), rather than silently reintroducing the bug one call site at a time.
    @Test("every fixed .system(size:) is either scaled or an allowlisted icon")
    func fixedSizeFontsAreScaledOrAllowlistedIcons() throws {
        // Keyed by path relative to Sources/; the value is how many icon fonts the file may hold. Counts,
        // not line numbers, so editing a file above an icon does not break the test.
        let iconAllowlist: [String: Int] = [
            "App/Permissions/OnboardingView.swift": 2,
            "Features/Settings/SettingsView.swift": 1,
            "Features/Settings/AppearancePreviews.swift": 1,
            "Features/CommandBar/CommandBarView.swift": 2,
            "Features/CommandBar/ShelfWindowButtons.swift": 2,
            "Features/AI/AIResultPanelController.swift": 2,
            "Features/Overlay/BiometricLockOverlay.swift": 2,
            "Features/Overlay/ToastView.swift": 1,
            "Features/Overlay/StackHUDWindowController.swift": 1,
            "Features/Overlay/OverlayRootView.swift": 6,
            "Features/Collections/EmojiPickerPopover.swift": 1,
            "Features/Collections/CollectionEditPopover.swift": 2,
            "Features/Collections/InlineCollectionCreator.swift": 4,
            "Features/Collections/CollectionEditor.swift": 2,
            "Features/Grid/ClipboardCard.swift": 2,
            "Features/Grid/ClipboardCard+Bodies.swift": 2,
            "Features/Grid/ClipboardCard+Pending.swift": 1,
            "Features/Grid/ClipboardCard+Parts.swift": 6,
            "Features/Grid/RemoteSourceTile.swift": 1,
            "Features/Settings/SettingsPaneHeader.swift": 1,
            "Features/Grid/ShelfDeleteConfirmation.swift": 1,
            "Features/Grid/FileCardBody.swift": 2,
            // The screenshot backdrop is fixed-size art, never shown to a user and deliberately not text-scaled.
            "Features/Marketing/MarketingBackdropView.swift": 2
        ]

        let sources = SourceTree.sources
        let pattern = try NSRegularExpression(pattern: #"\.font\(\.system\(size:"#)
        var offenders: [String] = []
        let files = try SourceTree.everySwiftFile()
        for file in files where file.lastPathComponent != "ScaledFont.swift" {
            let relativePath = file.path.replacingOccurrences(of: sources.path + "/", with: "")
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            let found = lines.count(where: { line in
                pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
            })
            let allowed = iconAllowlist[relativePath] ?? 0
            if found != allowed { offenders.append("\(relativePath): \(found) found, \(allowed) allowed") }
        }

        let scanned = Set(files.map { $0.path.replacingOccurrences(of: sources.path + "/", with: "") })
        let stale = iconAllowlist.keys.filter { !scanned.contains($0) }.sorted()

        #expect(stale.isEmpty, "icon allowlist names files that do not exist: \(stale.joined(separator: ", "))")
        #expect(
            offenders.isEmpty,
            "fixed, unscaled .system(size:) not on the icon allowlist: \(offenders.joined(separator: ", "))"
        )
    }
}

@Suite("Motion")
struct MotionRoutingTests {
    @Test("every SwiftUI animation goes through Motion so Reduce Motion is honoured")
    func animationsAreRoutedThroughMotion() throws {
        let raw =
            try NSRegularExpression(
                pattern: #"((?<!Motion)\.animation\((?!Motion\.)|withAnimation(?:\((?!Motion\.)|\s*\{))"#
            )
        var offenders: [String] = []
        let files = try SourceTree.everySwiftFile()
        for file in files where file.lastPathComponent != "Motion.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            if raw.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                offenders.append(file.lastPathComponent)
            }
        }

        #expect(offenders.isEmpty, "animations bypass Motion in: \(offenders.joined(separator: ", "))")
    }

    @Test("a symbol effect, which animates without .animation, is only used where Motion decides")
    func symbolEffectsAreRoutedThroughMotion() throws {
        var offenders: [String] = []
        let files = try SourceTree.everySwiftFile()
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() where line.contains(".symbolEffect(") && !line.contains("Motion.") {
                offenders.append("\(file.lastPathComponent):\(index + 1)")
            }
        }

        #expect(offenders.isEmpty, "symbol effects bypass Motion at: \(offenders.joined(separator: ", "))")
    }
}
