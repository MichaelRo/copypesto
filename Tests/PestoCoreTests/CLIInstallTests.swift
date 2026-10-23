// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The command-line installer only replaces its own link")
struct CLIInstallTests {
    private func temp() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("nothing there, or an old symlink, may be replaced; a real file may not")
    func whenChecked_thenOnlySymlinksAreReplaced() throws {
        let root = try temp()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("pesto")
        let file = root.appendingPathComponent("real")
        let link = root.appendingPathComponent("link")
        try Data("x".utf8).write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

        #expect(CLIInstall.mayReplace(missing))
        #expect(CLIInstall.mayReplace(link))
        #expect(!CLIInstall.mayReplace(file), "an unrelated file at that path must never be deleted")
    }

    @Test("the link goes to /usr/local/bin when that folder can be written, and to ~/.local/bin when it cannot")
    func whenChoosingTheFolder_thenAWritableOneWins() {
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(CLIInstall
            .linkFolder(shared: URL(fileURLWithPath: "/usr/local/bin"), sharedIsWritable: true, home: home)
            .path == "/usr/local/bin")
        #expect(CLIInstall.linkFolder(
            shared: URL(fileURLWithPath: "/usr/local/bin"),
            sharedIsWritable: false,
            home: home
        ).path == "/Users/someone/.local/bin")
    }
}
