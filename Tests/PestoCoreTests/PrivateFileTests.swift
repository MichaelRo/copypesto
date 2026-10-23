// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("PrivateFile", .serialized)
struct PrivateFileTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-private-file-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func mode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? Int) & 0o777
    }

    private func withUmask<T>(_ mask: mode_t, _ body: () throws -> T) rethrows -> T {
        let previous = umask(mask)
        defer { umask(previous) }
        return try body()
    }

    @Test
    func whenUmaskIsPermissive_thenTheFileIsStillOwnerOnly() throws {
        let url = directory.appendingPathComponent("a.json")

        try withUmask(0o000) { try PrivateFile.write(Data("secret".utf8), to: url) }

        #expect(try mode(of: url) == 0o600)
        #expect(try Data(contentsOf: url) == Data("secret".utf8))
    }

    @Test
    func whenTheTemporaryFileIsCreated_thenItIsOwnerOnlyBeforeAnyDataIsWritten() throws {
        let temporary = try withUmask(0o000) { try PrivateFile.createTemporary(in: directory) }
        defer { try? FileManager.default.removeItem(at: temporary.url) }
        close(temporary.descriptor)

        #expect(try mode(of: temporary.url) == 0o600)
    }

    @Test
    func whenAWiderFileAlreadyExists_thenItIsReplacedByAnOwnerOnlyOne() throws {
        let url = directory.appendingPathComponent("b.json")
        try Data("old".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)

        try PrivateFile.write(Data("new".utf8), to: url)

        #expect(try mode(of: url) == 0o600)
        #expect(try Data(contentsOf: url) == Data("new".utf8))
    }

    @Test
    func whenWritingSucceeds_thenNoTemporaryFileRemains() throws {
        let url = directory.appendingPathComponent("c.json")

        try PrivateFile.write(Data("x".utf8), to: url)
        try PrivateFile.write(Data("y".utf8), to: url)

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(names == ["c.json"])
    }

    @Test
    func whenTheTargetCannotBeReplaced_thenItThrowsAndLeavesNoTemporaryFile() throws {
        let url = directory.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        try Data("inside".utf8).write(to: url.appendingPathComponent("keep"))

        #expect(throws: (any Error).self) { try PrivateFile.write(Data("x".utf8), to: url) }

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(names == ["folder"])
    }
}
