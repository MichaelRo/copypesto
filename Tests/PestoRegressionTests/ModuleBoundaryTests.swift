// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Module boundaries and banned APIs")
struct ModuleBoundaryTests {
    private func codeLines(_ file: URL) throws -> [(number: Int, line: String)] {
        try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n").enumerated()
            .filter { !$0.element.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .map { ($0.offset + 1, $0.element) }
    }

    private func offenders(in files: [URL], matching pattern: String, except allowed: Set<String> = []) throws
        -> [String]
    {
        let expression = try NSRegularExpression(pattern: pattern)
        var found: [String] = []
        for file in files where !allowed.contains(file.lastPathComponent) {
            for (number, line) in try codeLines(file)
                where expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
            {
                found.append("\(SourceTree.relativePath(file)):\(number)")
            }
        }
        return found
    }

    @Test("no raw NSHostingView: SafeHostingView is the only one (a raw one crashes on macOS 26)")
    func noRawHostingView() throws {
        let files = try SourceTree.allSwiftFiles(in: SourceTree.minimumFileCounts)
        let found = try offenders(in: files, matching: #"NSHostingView\s*[<(]"#, except: ["SafeHostingView.swift"])
        #expect(found.isEmpty, "use SafeHostingView(pesto:): \(found)")
    }

    @Test("Shared does not import PestoCore: it sits below Core and Features")
    func sharedImportsNothingAbove() throws {
        let files = try SourceTree.swiftFiles(in: "Shared", minimum: 15)
        let found = try offenders(
            in: files, matching: #"^\s*(@preconcurrency\s+|@_exported\s+)?import\s+(\w+\s+)?PestoCore\b"#
        )
        #expect(found.isEmpty, "Shared may not import Core: \(found)")
    }

    @Test("Core never imports SwiftUI, in any spelling")
    func coreDoesNotImportSwiftUI() throws {
        let files = try SourceTree.swiftFiles(in: "Core", minimum: 120)
        let found = try offenders(
            in: files, matching: #"^\s*(@preconcurrency\s+|@_exported\s+)?import\s+(\w+\s+)?SwiftUI\b"#
        )
        #expect(found.isEmpty, "Core may not import SwiftUI: \(found)")
    }

    @Test("Pesto.yml packages are the three the app is allowed to depend on")
    func packagesAreAllowlisted() throws {
        let project = try String(
            contentsOf: SourceTree.repositoryRoot.appendingPathComponent("Pesto.yml"),
            encoding: .utf8
        )
        let block = try #require(project.components(separatedBy: "\npackages:\n").dropFirst().first?
            .components(separatedBy: "\ntargets:").first)
        let names = block.components(separatedBy: "\n")
            .filter { $0.hasPrefix("  ") && !$0.hasPrefix("    ") && $0.hasSuffix(":") }
            .map { $0.trimmingCharacters(in: .whitespaces).dropLast() }
            .map(String.init)
        #expect(Set(names) == ["PestoCore", "SnapshotTesting", "Sparkle"], "packages: \(names)")
    }

    @Test("no analytics SDK is named in the build files")
    func noAnalyticsInBuildFiles() throws {
        let forbidden = [
            "Sentry", "Mixpanel", "Amplitude", "Bugsnag", "Crashlytics", "Firebase", "Datadog", "Segment",
            "GoogleAnalytics", "PostHog", "Heap"
        ]
        for name in ["Pesto.yml", "Package.swift"] {
            let text = try String(contentsOf: SourceTree.repositoryRoot.appendingPathComponent(name), encoding: .utf8)
            for word in forbidden {
                #expect(!text.contains(word), "\(name) mentions \(word)")
            }
        }
    }

    @Test("a view reaches app logic through AppState, never AppDelegate or ScriptingContext; only the intents may")
    func featuresDoNotReachIntoTheApp() throws {
        let files = try SourceTree.swiftFiles(in: "Features", minimum: 60)
        let found = try offenders(
            in: files, matching: #"\b(AppDelegate|ScriptingContext)\b"#, except: [
                "OpenShelfIntent.swift",
                "HideClipContentsIntent.swift",
                "PasteFromPestoIntent.swift"
            ]
        )
        #expect(found.isEmpty, "these views reach past AppState: \(found)")
    }

    @Test("a card is dragged only through gatedDrag, so a covered card cannot be dragged out")
    func cardDragIsGated() throws {
        let card = try String(
            contentsOf: SourceTree.sources.appendingPathComponent("Features/Grid/ClipboardCard.swift"), encoding: .utf8
        )
        #expect(card.contains(".gatedDrag(allowed: concealment.allowsDrag)"))
        #expect(card.components(separatedBy: "onDrag {").count == 2, "only the helper may call onDrag")
        #expect(!card.contains("onDrag("), "onDrag must go through gatedDrag, whose provider is empty while covered")
    }

    @Test("a file card never asks the file system while it draws")
    func fileCardsDoNotStatInBody() throws {
        for name in [
            "Features/Grid/FileCardBody.swift", "Features/Grid/ClipboardCard.swift",
            "Features/Grid/ClipboardCard+Parts.swift"
        ] {
            let source = try String(contentsOf: SourceTree.sources.appendingPathComponent(name), encoding: .utf8)
            #expect(!source.contains("FileClip.missing(in:"), "\(name) checks files on the main thread")
        }
        let body = try String(
            contentsOf: SourceTree.sources.appendingPathComponent("Features/Grid/FileCardBody.swift"), encoding: .utf8
        )
        #expect(!body.contains("fileExists"), "FileCardBody stats files itself")
    }
}
