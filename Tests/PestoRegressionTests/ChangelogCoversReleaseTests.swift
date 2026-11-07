// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// The changelog stopped at 1.0.0 while four releases shipped. A version in `Pesto.yml` with no heading in
/// `CHANGELOG.md` fails here, so bumping the version is the reminder to write the entry.
@Suite("Changelog covers the release")
struct ChangelogCoversReleaseTests {
    @Test("every marketing version in Pesto.yml has a dated heading in CHANGELOG.md")
    func whenVersionIsSet_thenChangelogHasItsHeading() throws {
        let root = SourceTree.repositoryRoot
        let project = try String(contentsOf: root.appendingPathComponent("Pesto.yml"), encoding: .utf8)
        let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
        let versions = Set(project.matches(of: /MARKETING_VERSION:\s*"([^"]+)"/).map { String($0.output.1) })
        #expect(!versions.isEmpty)
        for version in versions {
            let heading = "## [\(version)] - "
            #expect(changelog.contains(heading), "CHANGELOG.md has no \"\(heading)YYYY-MM-DD\" section for \(version)")
        }
    }
}
