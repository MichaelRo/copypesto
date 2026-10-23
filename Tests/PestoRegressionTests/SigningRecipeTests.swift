// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// `make setup-signing` changes a developer's login keychain. The narrowing (one key, code signing only, a leaf
/// certificate) cannot be run on a build machine, so the script is pinned here and was exercised with stand-ins for
/// `security` and `sleep` when it was written.
@Suite("The development signing recipe")
struct SigningRecipeTests {
    private func script() throws -> String {
        try String(
            contentsOf: SourceTree.repositoryRoot.appendingPathComponent("scripts/setup-signing.sh"), encoding: .utf8
        )
    }

    @Test("the certificate is a leaf that can only sign code, and the key carries the identity's name")
    func whenCertificate_thenLeafCodeSigningOnly() throws {
        let text = try script()

        #expect(text.contains("basicConstraints=critical,CA:false"))
        #expect(text.contains("keyUsage=critical,digitalSignature"))
        #expect(!text.contains("keyCertSign"), "the certificate must not be able to sign other certificates")
        #expect(text.contains("-name \"$IDENTITY\""), "the key needs a friendlyName for the label match")
    }

    @Test("trust is for code signing only, and the partition list names one key unless the person asks for all")
    func whenTrustAndPartitions_thenNarrow() throws {
        let text = try script()

        #expect(text.contains("add-trusted-cert -p codeSign -r trustRoot"))
        #expect(text.contains("set-key-partition-list -S apple-tool:,apple:,codesign: -s -l \"$IDENTITY\""))
        #expect(text.contains("PESTO_SIGNING_WIDE"), "the old keychain-wide behavior stays one explicit switch away")
        #expect(!text.contains("-k \"\""), "an empty password on the command line fails and shows up in ps")
    }

    @Test("it says what it will change and waits before touching the keychain, and refuses to add a second identity")
    func whenStarted_thenItWarnsAndGuardsAgainstADuplicate() throws {
        let text = try script()

        #expect(text.contains("make ${SETUP_TARGET:-setup-signing} will, in your LOGIN keychain"))
        #expect(text.contains("sleep \"$WAIT\""))
        #expect(text.contains("a second one would make codesign ambiguous"))
    }

    @Test("the Makefile target runs the script and nothing else")
    func whenMakefile_thenItCallsTheScript() throws {
        let makefile = try String(
            contentsOf: SourceTree.repositoryRoot.appendingPathComponent("Makefile"), encoding: .utf8
        )

        #expect(makefile.contains("scripts/setup-signing.sh"))
        #expect(!makefile.contains("set-key-partition-list"), "the keychain commands live in the script")
    }
}
