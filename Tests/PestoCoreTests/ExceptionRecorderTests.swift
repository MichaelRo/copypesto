// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("ExceptionRecorder")
struct ExceptionRecorderTests {
    @Test("the report names the exception, its reason and the first frames")
    func whenFormatted_thenContainsNameReasonAndFrames() {
        let text = ExceptionRecorder.report(
            name: "NSInvalidArgumentException",
            reason: "bad keypath",
            callStack: ["frame0", "frame1"],
            date: Date(timeIntervalSince1970: 0)
        )

        #expect(text.contains("NSInvalidArgumentException"))
        #expect(text.contains("bad keypath"))
        #expect(text.contains("frame1"))
        #expect(text.contains("1970-01-01"))
    }

    @Test("only the first line of a long reason is kept, since a reason can quote stored values")
    func whenReasonIsLong_thenTruncated() {
        let reason = String(repeating: "x", count: 500) + "\nsecond line with a value"

        let text = ExceptionRecorder.report(name: "N", reason: reason, callStack: [], date: .now)

        #expect(!text.contains("second line"))
        #expect(!text.contains(String(repeating: "x", count: 250)))
    }

    @Test("the file is private to the owner, and can be deleted")
    func whenRecorded_thenOwnerOnlyAndDeletable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        ExceptionRecorder.record(report: "x", in: directory)
        let file = directory.appendingPathComponent("last-exception.txt")

        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)

        ExceptionRecorder.clear(in: directory)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("recording writes the report to last-exception.txt in the directory, replacing the previous one")
    func whenRecorded_thenFileHoldsLatestReport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        ExceptionRecorder.record(report: "first", in: directory)
        ExceptionRecorder.record(report: "second", in: directory)

        let written = try String(contentsOf: directory.appendingPathComponent("last-exception.txt"), encoding: .utf8)
        #expect(written == "second")
    }
}
