// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// A third-party action referenced by tag can change under us, and a workflow that holds signing secrets
/// makes that a supply-chain hole. Releases are built on the maintainer's Mac (`make release`), never in CI.
@Suite("CI workflows")
struct WorkflowSafetyTests {
    private static func workflows() throws -> [(name: String, text: String)] {
        try SourceTree.files(
            in: ".github/workflows", extensions: ["yml", "yaml"], minimum: 1, under: SourceTree.repositoryRoot
        ).map { try ($0.lastPathComponent, String(contentsOf: $0, encoding: .utf8)) }
    }

    @Test("every action is pinned to a full commit SHA")
    func actionsArePinned() throws {
        let pattern = try NSRegularExpression(pattern: #"uses:\s*([^\s@]+)@([^\s#]+)"#)
        var offenders: [String] = []
        for (name, text) in try Self.workflows() {
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let reference = Range(match.range(at: 2), in: text) else { continue }
                let pinned = text[reference].count == 40 && text[reference].allSatisfy(\.isHexDigit)
                if !pinned { offenders.append("\(name): \(text[reference])") }
            }
        }

        #expect(offenders.isEmpty, "pin to a commit SHA: \(offenders)")
    }

    @Test("only the protected release environment workflow may import a signing certificate or run on a version tag")
    func noSigningInCI() throws {
        for (name, text) in try Self.workflows() {
            let hasSigning = text.contains("security import")
            let hasTagTrigger = text.contains("tags:")
            if name == "release.yml" {
                if hasSigning || hasTagTrigger {
                    #expect(
                        text.contains("environment: release"),
                        "\(name) uses signing or tag triggers without `environment: release`"
                    )
                }
            } else {
                #expect(!hasSigning, "\(name) imports a certificate")
                #expect(!hasTagTrigger, "\(name) runs on tags: releases belong only in release.yml")
            }
        }
    }

    @Test("a workflow holds a read-only token, and no checkout keeps its credentials for later steps")
    func leastPrivilege() throws {
        for (name, text) in try Self.workflows() {
            #expect(text.contains("\npermissions:\n  contents: read"), "\(name) has no read-only permissions block")
            let checkouts = text.components(separatedBy: "uses: actions/checkout@").count - 1
            let withoutCredentials = text.components(separatedBy: "persist-credentials: false").count - 1
            #expect(checkouts == withoutCredentials, "\(name): every checkout needs persist-credentials: false")
        }
    }
}
