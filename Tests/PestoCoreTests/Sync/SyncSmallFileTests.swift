// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("A small sync file is read only when it is small")
struct SyncSmallFileTests {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("pesto-small-\(UUID().uuidString)", isDirectory: true)

    private func file(of size: Int) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("f-\(size)")
        try Data(repeating: 7, count: size).write(to: url)
        return url
    }

    @Test("a file at the limit is read whole")
    func whenAtTheLimit_thenRead() throws {
        let url = try file(of: SyncSmallFile.maxBytes)

        #expect(SyncSmallFile.read(url)?.count == SyncSmallFile.maxBytes)
    }

    @Test("a file over the limit is not read at all")
    func whenOverTheLimit_thenNil() throws {
        let url = try file(of: SyncSmallFile.maxBytes + 1)

        #expect(SyncSmallFile.read(url) == nil)
    }

    @Test("a folder or a pipe is refused before it is opened: opening a pipe waits for a writer")
    func whenNotARegularFile_thenNil() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pipe = folder.appendingPathComponent("pipe")
        #expect(mkfifo(pipe.path, 0o600) == 0)

        #expect(SyncSmallFile.read(pipe) == nil)
        #expect(SyncSmallFile.read(folder) == nil)
    }

    @Test("a missing file reads as nothing")
    func whenMissing_thenNil() {
        #expect(SyncSmallFile.read(folder.appendingPathComponent("nope")) == nil)
    }

    @Test("a dataless placeholder is not read: it would wait for the network on the calling thread")
    func whenDataless_thenNil() throws {
        let url = try file(of: 10)

        #expect(SyncSmallFile.read(url, flags: { _ in DatalessFile.flag }) == nil)
        #expect(SyncSmallFile.read(url, flags: { _ in 0 })?.count == 10)
    }
}
