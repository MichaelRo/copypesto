// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Core builds for macOS and iOS")
struct PlatformFenceTests {
    private static let platformFrameworks: Set<String> = [
        "AppKit", "ApplicationServices", "Carbon", "Cocoa", "CoreServices", "IOKit", "ServiceManagement", "UIKit"
    ]

    /// Files that exist only on the Mac, by Core directory. A number may shrink (a file became shared) and never
    /// grow: new code that both platforms can run is written unfenced, with only its platform calls inside `#if`.
    private static let macOnlyFileCeilings: [String: Int] = [
        "Import": 27, "Paste": 28, "Pasteboard": 10, "Runtime": 8, "Seeding": 8, "Storage": 3
    ]

    private struct Reading {
        var unfencedImports: [String] = []
        var isMacOnly = false
    }

    private static func read(_ file: URL) throws -> Reading {
        let lines = try String(contentsOf: file, encoding: .utf8)
            .trimmingCharacters(in: .newlines).components(separatedBy: "\n")
        var reading = Reading()
        var platformDepths: [Bool] = []
        var outerClosedAt: Int?
        var outerHasElse = false
        for (index, line) in lines.enumerated() {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("#if") {
                platformDepths.append(text.contains("os("))
            } else if text.hasPrefix("#else"), platformDepths.count == 1 {
                outerHasElse = true
            } else if text.hasPrefix("#endif") {
                platformDepths.removeLast()
                if platformDepths.isEmpty, outerClosedAt == nil { outerClosedAt = index }
            } else if text.hasPrefix("import ") {
                let module = text.dropFirst("import ".count).split(separator: ".").first.map(String.init) ?? ""
                if platformFrameworks.contains(module), !platformDepths.contains(true) {
                    reading.unfencedImports.append("\(file.lastPathComponent):\(index + 1)")
                }
            }
        }
        let opensFenced = lines.count > 3
            && (lines[1] == "#if os(macOS)" || (lines[1] == "#if DEBUG" && lines[2] == "#if os(macOS)"))
        reading.isMacOnly = opensFenced && outerClosedAt == lines.count - 1 && !outerHasElse
        return reading
    }

    @Test("a Core file imports a platform framework only inside an #if os(…) block")
    func platformImportsAreFenced() throws {
        let offenders = try SourceTree.swiftFiles(in: "Core", minimum: 120)
            .flatMap { try Self.read($0).unfencedImports }

        #expect(offenders.isEmpty, "wrap the import in #if os(macOS): \(offenders.sorted().joined(separator: ", "))")
    }

    @Test("the number of Mac-only files in a Core directory never grows")
    func macOnlyFilesOnlyShrink() throws {
        var counts: [String: Int] = [:]
        let core = SourceTree.sources.appendingPathComponent("Core").path + "/"
        for file in try SourceTree.swiftFiles(in: "Core", minimum: 120) where try Self.read(file).isMacOnly {
            let directory = file.path.replacingOccurrences(of: core, with: "").split(separator: "/").first
            counts[directory.map(String.init) ?? "", default: 0] += 1
        }

        #expect(
            counts == Self.macOnlyFileCeilings,
            "a new shared file is not fenced; if a file became shared, lower its directory's number"
        )
    }
}
