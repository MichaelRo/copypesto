// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("A file a provider has listed but not downloaded is not read yet")
struct SyncFileAvailabilityTests {
    private func file() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pesto-avail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("segment.pestolog")
        try Data("x".utf8).write(to: url)
        return url
    }

    @Test("an ordinary file is readable")
    func whenOrdinary_thenReadable() throws {
        #expect(try SyncFileAvailability.isReadable(file(), flags: { _ in 0 }))
    }

    @Test("a dataless placeholder (Dropbox, Google Drive and others use them) is not readable yet")
    func whenDataless_thenNotReadable() throws {
        #expect(try !SyncFileAvailability.isReadable(file(), flags: { _ in SyncFileAvailability.datalessFlag }))
    }

    @Test("a missing file is not readable")
    func whenMissing_thenNotReadable() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString)")
        #expect(!SyncFileAvailability.isReadable(url, flags: { _ in 0 }))
    }
}
