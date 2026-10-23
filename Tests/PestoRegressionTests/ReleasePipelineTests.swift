// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// `make release` once ran its team id through a placeholder that `envsubst` never replaced, and Sparkle
/// (the code that installs updates) was pinned by a tag that can move.
@Suite("Release pipeline")
struct ReleasePipelineTests {
    private func text(_ relative: String) throws -> String {
        try String(contentsOf: SourceTree.repositoryRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    private func renderExportOptions(team: String) throws -> (code: Int32, output: String) {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: out) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            SourceTree.repositoryRoot.appendingPathComponent("scripts/render-export-options.sh").path, team, out.path
        ]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let rendered = (try? String(contentsOf: out, encoding: .utf8)) ?? ""
        return (process.terminationStatus, rendered + (String(bytes: data, encoding: .utf8) ?? ""))
    }

    @Test("the export options carry the team id, with no placeholder left")
    func exportOptionsAreRendered() throws {
        let result = try renderExportOptions(team: "ABCDE12345")
        #expect(result.code == 0, "\(result.output)")
        #expect(result.output.contains("<string>ABCDE12345</string>"))
        #expect(!result.output.contains("$("), "a placeholder survived")
        #expect(!result.output.contains("TEAM_ID_PLACEHOLDER"), "a placeholder survived")
    }

    @Test("a missing or malformed team id stops the export instead of signing with a bad one")
    func badTeamIDsAreRefused() throws {
        for team in ["", "abc", "ABCDE1234", "ABCDE123456", "$(APPLE_TEAM_ID)"] {
            #expect(try renderExportOptions(team: team).code != 0, "accepted '\(team)'")
        }
    }

    @Test("the archive and export steps both receive the team")
    func makefilePassesTheTeam() throws {
        let makefile = try text("Makefile")
        #expect(makefile.contains("DEVELOPMENT_TEAM=$(APPLE_TEAM_ID)"), "xcodebuild archive is not given the team")
        #expect(!makefile.contains("envsubst"), "the placeholder is rendered by scripts/render-export-options.sh")
        #expect(makefile.contains("scripts/render-export-options.sh"))
    }

    @Test("a clean checkout can install the pinned tools, and CI stops when the install fails")
    func installToolsWorksOnACleanCheckoutAndCIStopsOnFailure() throws {
        let script = try text("scripts/install-tools.sh")
        let mkdir = try #require(script.range(of: "mkdir -p \"$TOOLS\""))
        let firstFetch = try #require(script.range(of: "\nif [[ ! -x"))
        #expect(mkdir.lowerBound < firstFetch.lowerBound, "curl cannot write into a folder that does not exist yet")

        let workflow = try text(".github/workflows/ci.yml")
        #expect(
            !workflow.contains("echo \"$(scripts/install-tools.sh)\""),
            "echo hides the failure of the command inside it"
        )
    }

    @Test("every package the app builds with is pinned to a commit, not a tag")
    func packagesArePinnedToRevisions() throws {
        let project = try text("Pesto.yml")
        let block = try #require(project.components(separatedBy: "\npackages:\n").dropFirst().first?
            .components(separatedBy: "\ntargets:").first)
        var packages: [[String]] = []
        for line in block.components(separatedBy: "\n") where !line.isEmpty {
            if line.hasPrefix("  "),
               !line.hasPrefix("   ") { packages.append([line]) } else { packages[packages.count - 1].append(line) }
        }
        let external = packages.map { $0.joined(separator: "\n") }.filter { $0.contains("url:") }
        #expect(external.count == 2, "\(external)")
        for package in external {
            #expect(
                package.range(of: #"revision: "?[0-9a-f]{40}"?"#, options: .regularExpression) != nil,
                "not pinned by revision: \(package)"
            )
            #expect(!package.contains("exactVersion") && !package.contains("branch:"), "\(package)")
        }
    }

    @Test("every tool CI downloads is checked against a SHA-256 in tool-versions.env")
    func toolDownloadsAreChecksummed() throws {
        let versions = try text("scripts/tool-versions.env")
        let installer = try text("scripts/install-tools.sh")
        for tool in ["SWIFTFORMAT", "SWIFTLINT", "XCODEGEN"] {
            #expect(
                versions.range(of: "\(tool)_SHA256=[0-9a-f]{64}", options: .regularExpression) != nil,
                "\(tool) has no checksum"
            )
            #expect(installer.contains("$\(tool)_SHA256"), "\(tool) checksum is not checked")
        }
        #expect(installer.contains("shasum -a 256"))
        let workflow = try text(".github/workflows/ci.yml")
        #expect(!workflow.contains("brew install"), "an unpinned tool is installed in CI")
    }

    @Test("the committed package pins match Pesto.yml and cover the transitive packages too")
    func resolvedFileMatchesTheProject() throws {
        let resolved = try #require(JSONSerialization.jsonObject(
            with: Data(contentsOf: SourceTree.repositoryRoot.appendingPathComponent("Pesto.resolved"))
        ) as? [String: Any])
        let pins = try #require(resolved["pins"] as? [[String: Any]])
        let revisions = Dictionary(uniqueKeysWithValues: pins.compactMap { pin -> (String, String)? in
            guard let id = pin["identity"] as? String, let state = pin["state"] as? [String: Any],
                  let revision = state["revision"] as? String else { return nil }
            return (id, revision)
        })
        let project = try text("Pesto.yml")
        for (identity, expected) in [
            ("sparkle", "066e75a8b3e99962685d6a90cdd5293ebffd9261"),
            ("swift-snapshot-testing", "ad5e3190cc63dc288f28546f9c6827efc1e9d495")
        ] {
            #expect(project.contains("revision: \(expected)"), "Pesto.yml does not pin \(identity)")
            #expect(revisions[identity] == expected, "Pesto.resolved disagrees about \(identity)")
        }
        #expect(revisions["swift-syntax"] != nil && revisions["swift-custom-dump"] != nil, "transitive pins missing")
    }
}
