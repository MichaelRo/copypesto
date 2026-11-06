// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Testing

/// `scripts/verify-download.sh` replaces the release checklist's hand-run `shasum`, `codesign`, `spctl` and `stapler`
/// lines. A real signed image needs a release, so these cover what does not: usage, a hash that does not match
/// (before anything is mounted), and a file that is not a disk image. The full pass is run once on a real download.
@Suite("verify-download.sh")
struct VerifyDownloadScriptTests {
    private struct Result {
        let code: Int32
        let output: String
    }

    private func run(_ arguments: [String]) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [SourceTree.repositoryRoot.appendingPathComponent("scripts/verify-download.sh").path]
            + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(code: process.terminationStatus, output: String(bytes: data, encoding: .utf8) ?? "")
    }

    private func notAnImage(_ contents: String = "not a disk image") throws -> (url: URL, sha: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Pesto-\(UUID().uuidString).dmg")
        let data = Data(contents.utf8)
        try data.write(to: url)
        return (url, SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }

    @Test("no file, or a missing one, is a usage error")
    func whenNoFile_thenUsage() throws {
        #expect(try run([]).code == 2)
        #expect(try run(["/nonexistent/Pesto.dmg"]).code == 2)
    }

    @Test("a hash that does not match fails before anything is opened")
    func whenTheHashDiffers_thenItFailsAtOnce() throws {
        let file = try notAnImage()
        defer {
            try? FileManager.default.removeItem(at: file.url)
            try? FileManager.default.removeItem(atPath: file.url.path + ".sha256")
        }
        let result = try run([file.url.path, String(repeating: "0", count: 64)])
        #expect(result.code == 1)
        #expect(result.output.contains("FAIL  SHA-256"))
        #expect(!result.output.contains("disk image"), "it stopped before mounting")
    }

    @Test("a .sha256 file beside the image is the expected hash")
    func whenASha256FileSitsBeside_thenItIsUsed() throws {
        let file = try notAnImage()
        defer {
            try? FileManager.default.removeItem(at: file.url)
            try? FileManager.default.removeItem(atPath: file.url.path + ".sha256")
        }
        try String(repeating: "0", count: 64).write(
            to: URL(fileURLWithPath: file.url.path + ".sha256"), atomically: true, encoding: .utf8
        )
        #expect(try run([file.url.path]).code == 1)
        try "\(file.sha)  \(file.url.lastPathComponent)\n".write(
            to: URL(fileURLWithPath: file.url.path + ".sha256"), atomically: true, encoding: .utf8
        )
        let result = try run([file.url.path])
        #expect(result.output.contains("ok    SHA-256 \(file.sha)"))
    }

    @Test("a file with the right hash that is not a disk image fails")
    func whenItIsNotADiskImage_thenItFails() throws {
        let file = try notAnImage()
        defer {
            try? FileManager.default.removeItem(at: file.url)
            try? FileManager.default.removeItem(atPath: file.url.path + ".sha256")
        }
        let result = try run([file.url.path, file.sha])
        #expect(result.code == 1)
        #expect(result.output.contains("does not open as a disk image"))
    }
}
