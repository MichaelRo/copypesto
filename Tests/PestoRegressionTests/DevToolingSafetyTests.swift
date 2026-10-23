// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// A development build shares the shipped identity, so a `make` target that deletes the Keychain key,
/// the preferences or the store deletes the developer's real history. Those targets must be opt-in.
@Suite("Development tooling")
struct DevToolingSafetyTests {
    private struct Target {
        let name: String
        let prerequisites: String
        let recipe: String
    }

    private static func makefileTargets() throws -> [Target] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Makefile"), encoding: .utf8)
        var heads: [(name: String, prerequisites: String)] = []
        var recipes: [[String]] = []
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("\t"), !recipes.isEmpty {
                recipes[recipes.count - 1].append(line)
            } else if let match = line.firstMatch(of: /^([A-Za-z0-9_.-]+):(?!=)([^#]*)/) {
                heads.append((String(match.1), String(match.2)))
                recipes.append([])
            }
        }
        return zip(heads, recipes).map {
            Target(name: $0.name, prerequisites: $0.prerequisites, recipe: $1.joined(separator: "\n"))
        }
    }

    private static let destructive = [
        "delete-generic-password", "defaults delete", "rm -rf ~/Library", "rm -rf \"~/Library", "tccutil reset"
    ]

    @Test("every make target that deletes the real Keychain key, preferences or store needs PESTO_DEV_RESET")
    func destructiveTargetsAreOptIn() throws {
        let targets = try Self.makefileTargets()
        #expect(targets.count > 20, "the Makefile was not parsed")
        let destructiveTargets = targets.filter { target in Self.destructive.contains { target.recipe.contains($0) } }
        #expect(destructiveTargets.count >= 2, "expected reset-onboarding and reset-dev-state")
        for target in destructiveTargets {
            #expect(
                target.prerequisites.contains("require-dev-reset"),
                "\(target.name) deletes real state without require-dev-reset"
            )
        }
    }

    @Test("the guard refuses unless PESTO_DEV_RESET=1")
    func guardRefusesByDefault() throws {
        let targets = try Self.makefileTargets()
        let guardTarget = try #require(targets.first { $0.name == "require-dev-reset" })
        #expect(guardTarget.recipe.contains("PESTO_DEV_RESET"))
        #expect(guardTarget.recipe.contains("exit 1"))
    }

    @Test("reset-onboarding never deletes the key while a store exists")
    func keyDeletionChecksForAStore() throws {
        let targets = try Self.makefileTargets()
        let onboarding = try #require(targets.first { $0.name == "reset-onboarding" })
        let recipe = onboarding.recipe
        let check = try #require(recipe.range(of: "clips.store"), "no check for an existing store")
        let deletion = try #require(recipe.range(of: "delete-generic-password"))
        #expect(check.lowerBound < deletion.lowerBound, "the store is checked after the key is deleted")
    }

    @Test("reset-fresh-install moves the history aside and never deletes it or its key")
    func freshInstallKeepsTheHistory() throws {
        let targets = try Self.makefileTargets()
        let fresh = try #require(targets.first { $0.name == "reset-fresh-install" })
        #expect(fresh.prerequisites.contains("require-dev-reset"))
        #expect(fresh.recipe.contains("mv \"$(APP_SUPPORT_DIR)\""), "the history is not moved aside")
        #expect(!fresh.recipe.contains("rm -rf"), "a fresh install must not delete the history")
        #expect(!fresh.recipe.contains("delete-generic-password"), "deleting the key would strand the history")
    }
}
