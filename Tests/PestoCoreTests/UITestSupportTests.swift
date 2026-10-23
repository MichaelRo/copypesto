// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("UITestSupport")
struct UITestSupportTests {
    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-uitest-support-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("a fresh directory is not ready")
    func whenNothingWritten_thenNotReady() {
        let directory = makeDirectory()
        #expect(UITestSupport.readyMarker(in: directory) == nil)
    }

    @Test("the ready marker records how many items were seeded")
    func whenMarkedReady_thenCountReadable() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try UITestSupport.markReady(seededCount: 14, processID: 4242, in: directory)

        #expect(UITestSupport.readyMarker(in: directory)?.seededCount == 14)
        #expect(UITestSupport.readyMarker(in: directory)?.processID == 4242)
    }

    @Test("an enqueued command is drained once, then the queue is empty")
    func whenCommandEnqueued_thenDrainedOnce() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try UITestCommandQueue.enqueue(.showOverlay, in: directory)

        #expect(UITestCommandQueue.drain(in: directory) == [.showOverlay])
        #expect(UITestCommandQueue.drain(in: directory).isEmpty)
    }

    @Test("commands are drained in the order they were enqueued")
    func whenSeveralEnqueued_thenOrderPreserved() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try UITestCommandQueue.enqueue(.showOverlay, in: directory)
        try UITestCommandQueue.enqueue(.openSettings, in: directory)
        try UITestCommandQueue.enqueue(.hideOverlay, in: directory)

        #expect(UITestCommandQueue.drain(in: directory) == [.showOverlay, .openSettings, .hideOverlay])
    }

    @Test("a directory that does not exist yet drains to nothing")
    func whenNoQueueDirectory_thenEmpty() {
        #expect(UITestCommandQueue.drain(in: makeDirectory()).isEmpty)
    }

    @Test("an unknown command file is discarded without blocking the ones after it")
    func whenUnknownCommandFile_thenSkippedAndRemoved() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try UITestCommandQueue.enqueue(.showOverlay, in: directory)
        let queue = directory.appendingPathComponent(UITestCommandQueue.directoryName)
        try Data("explode".utf8).write(to: queue.appendingPathComponent("00000000000000000000-junk.cmd"))

        #expect(UITestCommandQueue.drain(in: directory) == [.showOverlay])
        #expect(try FileManager.default.contentsOfDirectory(atPath: queue.path).isEmpty)
    }
}
