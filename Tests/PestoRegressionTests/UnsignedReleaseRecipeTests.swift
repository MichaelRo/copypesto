// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// Pesto 1.0 ships signed with a self-signed identity, not Developer ID. The hardened runtime would make Sparkle fail
/// library validation (no Team ID), and an ad hoc signature would change the app's identity on every update.
@Suite("The unsigned release recipe")
struct UnsignedReleaseRecipeTests {
    private func text(_ relative: String) throws -> String {
        try String(contentsOf: SourceTree.repositoryRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    @Test("the release identity is made by the same script as the development one, under its own name")
    func whenReleaseIdentity_thenSameScriptOtherName() throws {
        let makefile = try text("Makefile")
        let script = try text("scripts/setup-signing.sh")

        #expect(makefile.contains("setup-release-signing:"))
        #expect(makefile.contains("DEV_SIGN_IDENTITY=\"$(RELEASE_SIGN_IDENTITY)\""))
        #expect(makefile.contains("RELEASE_SIGN_IDENTITY = Pesto Release"))
        #expect(script.contains("make ${SETUP_TARGET:-setup-signing} will"), "the notice names the target that ran")
        #expect(script.contains("export it from Keychain Access"), "the release identity needs a backup reminder")
    }

    @Test("release-unsigned signs with the named identity, without the hardened runtime, and refuses ad hoc")
    func whenReleaseUnsigned_thenStableIdentityNoRuntime() throws {
        let makefile = try text("Makefile")
        let script = try text("scripts/release-unsigned.sh")

        #expect(makefile.contains("release-unsigned:"))
        #expect(makefile.contains("scripts/release-unsigned.sh"))
        #expect(!script.contains("--options runtime"), "Sparkle fails library validation under the runtime")
        #expect(!script.contains("--deep --sign"), "sign each nested piece, inside out, never --deep")
        #expect(script.contains("security find-identity -v -p codesigning"), "it must find the identity first")
        #expect(script.contains("PESTO_RELEASE_IDENTITY"))
        #expect(script.contains("refusing to sign ad hoc"))
        #expect(script.contains("codesign --verify --deep --strict"))
        #expect(script.contains("PestoAllowsTestHooks"), "a release app must not allow -UITestMode")
    }

    @Test("Sparkle's pieces and the extension are signed before the app, and the disk image gets a checksum file")
    func whenSigning_thenInsideOutAndChecksum() throws {
        let script = try text("scripts/release-unsigned.sh")
        let sparkle = try #require(script.range(of: "Autoupdate"))
        let framework = try #require(script.range(of: "Sparkle.framework\""))
        let appex = try #require(script.range(of: "PestoControls.appex"))
        let app = try #require(script.range(of: "\"$ENTITLEMENTS\" \"$APP\""))

        #expect(sparkle.lowerBound < framework.lowerBound)
        #expect(framework.lowerBound < appex.lowerBound)
        #expect(appex.lowerBound < app.lowerBound)
        #expect(script.contains("shasum -a 256"))
        #expect(script.contains("make-dmg.sh"))
    }
}
