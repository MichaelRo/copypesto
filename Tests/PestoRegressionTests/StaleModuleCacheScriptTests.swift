// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// After the Sparkle 2.10.1 bump, `make install` and both benches failed with
/// "Sparkle.framework/Headers/SUAppcastItem.h
/// has been modified since the module file ... was built": the precompiled module cache in `.build` outlived the
/// package it was made from. `scripts/clear-stale-module-cache.sh` runs in `make generate` and clears that cache when
/// `Pesto.resolved` (the committed package pins) differs from what the cache was built under.
@Suite("clear-stale-module-cache.sh")
struct StaleModuleCacheScriptTests {
    private struct Checkout {
        let root: URL
        var cache: URL {
            root.appendingPathComponent(".build/xcode/Build/Intermediates.noindex/SwiftExplicitPrecompiledModules")
        }

        var otherBuildCache: URL {
            root
                .appendingPathComponent(
                    ".build/xcode-release/Build/Intermediates.noindex/SwiftExplicitPrecompiledModules"
                )
        }

        var untouched: URL {
            root.appendingPathComponent(".build/xcode/Build/Intermediates.noindex/Pesto.build/keep.o")
        }
    }

    private func makeCheckout(pins: String) throws -> Checkout {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("stale-module-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("scripts"), withIntermediateDirectories: true
        )
        let script = SourceTree.repositoryRoot.appendingPathComponent("scripts/clear-stale-module-cache.sh")
        try FileManager.default.copyItem(
            at: script,
            to: root.appendingPathComponent("scripts/clear-stale-module-cache.sh")
        )
        try pins.write(to: root.appendingPathComponent("Pesto.resolved"), atomically: true, encoding: .utf8)
        return Checkout(root: root)
    }

    private func fill(_ checkout: Checkout) throws {
        for directory in [checkout.cache, checkout.otherBuildCache, checkout.untouched.deletingLastPathComponent()] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data("module".utf8).write(to: checkout.cache.appendingPathComponent("Sparkle.pcm"))
        try Data("module".utf8).write(to: checkout.otherBuildCache.appendingPathComponent("Sparkle.pcm"))
        try Data("object".utf8).write(to: checkout.untouched)
    }

    private func run(_ checkout: Checkout) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [checkout.root.appendingPathComponent("scripts/clear-stale-module-cache.sh").path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    @Test("with no record of the pins, the module caches of every build folder are cleared and the pins recorded")
    func whenNoStamp_thenCachesAreCleared() throws {
        let checkout = try makeCheckout(pins: "sparkle 2.10.1")
        defer { try? FileManager.default.removeItem(at: checkout.root) }
        try fill(checkout)
        #expect(try run(checkout) == 0)
        #expect(!exists(checkout.cache))
        #expect(!exists(checkout.otherBuildCache))
        #expect(exists(checkout.untouched), "only the module cache goes, not the build's objects")
        #expect(exists(checkout.root.appendingPathComponent(".build/package-pins.sha")))
    }

    @Test("with the same pins, a cache built since is left alone")
    func whenPinsAreUnchanged_thenCachesStay() throws {
        let checkout = try makeCheckout(pins: "sparkle 2.10.1")
        defer { try? FileManager.default.removeItem(at: checkout.root) }
        try fill(checkout)
        #expect(try run(checkout) == 0)
        try fill(checkout)
        #expect(try run(checkout) == 0)
        #expect(exists(checkout.cache))
        #expect(exists(checkout.otherBuildCache))
    }

    @Test("when the pins change, the caches go again")
    func whenPinsChange_thenCachesAreClearedAgain() throws {
        let checkout = try makeCheckout(pins: "sparkle 2.10.1")
        defer { try? FileManager.default.removeItem(at: checkout.root) }
        try fill(checkout)
        #expect(try run(checkout) == 0)
        try fill(checkout)
        try "sparkle 2.11.0".write(
            to: checkout.root.appendingPathComponent("Pesto.resolved"), atomically: true, encoding: .utf8
        )
        #expect(try run(checkout) == 0)
        #expect(!exists(checkout.cache))
        #expect(exists(checkout.untouched))
    }

    @Test("a checkout that has never been built has nothing to clear and is not an error")
    func whenThereIsNoBuildFolder_thenItSucceeds() throws {
        let checkout = try makeCheckout(pins: "sparkle 2.10.1")
        defer { try? FileManager.default.removeItem(at: checkout.root) }
        #expect(try run(checkout) == 0)
    }
}
