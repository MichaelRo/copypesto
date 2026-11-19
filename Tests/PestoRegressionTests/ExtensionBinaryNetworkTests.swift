// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// Extensions (`PestoAutoFill`, `PestoShare`, `PestoWidget`, `PestoControls`) link `PestoCoreExtension` (the slim
/// `PestoCore` target) and never `PestoCoreNetworking`. Proving "no network code" requires inspecting the built
/// binary/object symbols, not just source text.
@Suite("Extension Core binary carries no network symbols")
struct ExtensionBinaryNetworkTests {
    private static let forbiddenSymbolFragments = [
        "URLMetadataFetcher",
        "LinkPreviewLoader",
        "RemoteGIFFetcher",
        "BoundedDownload",
        "LPMetadataProvider",
        "NSURLSession",
        "URLSession"
    ]

    private static let extensionTargets = [
        "PestoControls",
        "PestoShare",
        "PestoAutoFill",
        "PestoWidget"
    ]

    private static func coreObjectFiles() throws -> [URL] {
        let buildRoot = SourceTree.repositoryRoot.appendingPathComponent(".build")
        let candidates = [
            buildRoot.appendingPathComponent("out/Products/Debug/PestoCore.o"),
            buildRoot.appendingPathComponent("arm64-apple-macosx/debug/PestoCore.o")
        ]
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return [candidate]
        }

        let dirCandidates = [
            buildRoot.appendingPathComponent("out/Intermediates.noindex/PestoCore.build"),
            buildRoot.appendingPathComponent("arm64-apple-macosx/debug/PestoCore.build")
        ]
        for dir in dirCandidates where FileManager.default.fileExists(atPath: dir.path) {
            if let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) {
                let objs = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "o" }
                if !objs.isEmpty { return objs }
            }
        }
        Issue.record("could not locate built PestoCore.o under \(buildRoot.path)")
        return []
    }

    private static func runNM(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nm")
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(
            process.terminationStatus == 0,
            "nm failed (\(process.terminationStatus)): \(String(decoding: errData, as: UTF8.self))"
        )
        return String(decoding: outData, as: UTF8.self)
    }

    @Test("when inspecting built PestoCore object symbols, no link-preview or URLSession symbols exist")
    func whenInspectingBuiltCore_thenNoNetworkSymbolsPresent() throws {
        let objects = try Self.coreObjectFiles()
        #expect(!objects.isEmpty, "expected at least one PestoCore object file")

        let allSymbols = try Self.runNM(arguments: objects.map(\.path))
        let symbolLines = allSymbols.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(symbolLines.count > 100, "nm returned too few symbols (\(symbolLines.count))")

        let undefinedSymbols = try Self.runNM(arguments: ["-u"] + objects.map(\.path))
        let combined = allSymbols + "\n" + undefinedSymbols

        var hits: [String] = []
        for fragment in Self.forbiddenSymbolFragments where combined.contains(fragment) {
            hits.append(fragment)
        }
        #expect(hits.isEmpty, "built PestoCore contains forbidden network symbols: \(hits)")
    }

    @Test("when inspecting Pesto.yml, extension targets depend on PestoCoreExtension and never PestoCoreNetworking")
    func whenInspectingPestoYml_thenExtensionsLinkSlimCoreOnly() throws {
        let project = try String(
            contentsOf: SourceTree.repositoryRoot.appendingPathComponent("Pesto.yml"),
            encoding: .utf8
        )
        let targetsSection = try #require(
            project.components(separatedBy: "\ntargets:\n").dropFirst().first?
                .components(separatedBy: "\nschemes:").first
        )

        for target in Self.extensionTargets {
            let marker = "\n  \(target):\n"
            let afterTarget = try #require(
                ("\n" + targetsSection).components(separatedBy: marker).dropFirst().first,
                "missing target \(target) in Pesto.yml"
            )
            let nextTargetPattern = try NSRegularExpression(pattern: #"\n  [A-Za-z]"#)
            let nsAfter = afterTarget as NSString
            let nextRange = nextTargetPattern.firstMatch(
                in: afterTarget,
                range: NSRange(location: 0, length: nsAfter.length)
            )?.range
            let targetBlock = nextRange.map { nsAfter.substring(to: $0.location) } ?? afterTarget
            #expect(
                targetBlock.contains("product: PestoCoreExtension"),
                "\(target) must depend on product: PestoCoreExtension"
            )
            #expect(
                !targetBlock.contains("PestoCoreNetworking"),
                "\(target) must not depend on PestoCoreNetworking"
            )
        }
    }

    @Test("when scanning extension sources, none import PestoCoreNetworking")
    func whenScanningExtensionSources_thenNoneImportNetworking() throws {
        let files = try SourceTree.swiftFiles(in: "Widget", minimum: 10)
            + SourceTree.swiftFiles(in: "Controls", minimum: 1)
            + SourceTree.swiftFiles(in: "MobileShare", minimum: 3)
            + SourceTree.swiftFiles(in: "MobileAutoFill", minimum: 2)
            + SourceTree.swiftFiles(in: "MobileWidget", minimum: 2)
        var offenders: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.range(of: #"\bPestoCoreNetworking\b"#, options: .regularExpression) != nil {
                offenders.append(SourceTree.relativePath(file))
            }
        }
        #expect(offenders.isEmpty, "extension sources must not reference PestoCoreNetworking: \(offenders)")
    }
}
