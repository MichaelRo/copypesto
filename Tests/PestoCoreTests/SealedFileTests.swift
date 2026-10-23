// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("A cache file sealed like the store")
struct SealedFileTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sealed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("what is written reads back, and the file on disk holds none of it")
    func whenWritten_thenItReadsBackAndTheFileIsCiphertext() throws {
        let directory = try folder()
        let file = SealedFile(url: directory.appendingPathComponent("cache.bin"))
        let secret = Data("Quarterly layoffs plan - internal.example.com".utf8)

        try file.write(secret)

        #expect(file.read() == secret)
        let onDisk = try Data(contentsOf: file.url)
        #expect(onDisk.range(of: Data("layoffs".utf8)) == nil)
        #expect(onDisk.range(of: Data("internal.example.com".utf8)) == nil)
    }

    @Test("a plaintext file left by an older version reads as nothing and is removed")
    func whenThePlaintextOfAnOlderVersion_thenItIsRemoved() throws {
        let directory = try folder()
        let url = directory.appendingPathComponent("metadata-cache.json")
        try Data(#"{"abc":{"title":"Private page"}}"#.utf8).write(to: url)

        #expect(SealedFile(url: url).read() == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("a sealed file moved to another name does not open")
    func whenMovedToAnotherName_thenItDoesNotOpen() throws {
        let directory = try folder()
        let original = SealedFile(url: directory.appendingPathComponent("one.bin"))
        try original.write(Data("secret".utf8))
        let moved = directory.appendingPathComponent("two.bin")
        try FileManager.default.copyItem(at: original.url, to: moved)

        #expect(SealedFile(url: moved).read() == nil)
    }

    @Test("removing it leaves nothing, and reading a missing file is nothing")
    func whenRemoved_thenGone() throws {
        let directory = try folder()
        let file = SealedFile(url: directory.appendingPathComponent("cache.bin"))
        #expect(file.read() == nil)
        try file.write(Data("x".utf8))
        file.remove()
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
    }
}
