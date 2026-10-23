// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import Testing
@testable import Pesto

@Suite("Running a detected action", .serialized)
@MainActor
struct EntityActionRunnerTests {
    private final class Opened: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        func add(_ url: URL) {
            lock.withLock { urls.append(url) }
        }

        var all: [URL] {
            lock.withLock { urls }
        }
    }

    @Test("a date is opened as a calendar file containing the event")
    func whenDate_thenICSFileOpened() throws {
        let opened = Opened()
        let start = Date(timeIntervalSince1970: 1_800_003_600)

        EntityActionRunner.run(.date(.init(title: "Team lunch", start: start, hasTime: true)), open: { opened.add($0) })

        let url = try #require(opened.all.first)
        #expect(url.pathExtension == "ics")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("SUMMARY:Team lunch") && text.contains("DTSTART:20270115T090000Z"))
        try? FileManager.default.removeItem(at: url)
    }

    @Test("the calendar file is removed shortly after it is opened, since it holds the copied text")
    func whenDateOpened_thenFileIsRemovedAfterADelay() async throws {
        let opened = Opened()

        EntityActionRunner.run(
            .date(.init(title: "Team lunch", start: .now, hasTime: false)),
            removeAfter: .milliseconds(50),
            open: { opened.add($0) }
        )
        let url = try #require(opened.all.first)
        #expect(FileManager.default.fileExists(atPath: url.path))

        try await Task.sleep(for: .milliseconds(400))

        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("the launch sweep also removes calendar files left behind by an earlier run")
    func whenSweeping_thenLeftoverCalendarFilesGo() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pesto-ics-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let leftover = root.appendingPathComponent("Pesto event ab12cd34.ics")
        let other = root.appendingPathComponent("holiday.ics")
        try Data("x".utf8).write(to: leftover)
        try Data("x".utf8).write(to: other)
        defer { try? FileManager.default.removeItem(at: root) }

        QuickLookPreviewController.sweepStaleTempFiles(in: root)

        #expect(!FileManager.default.fileExists(atPath: leftover.path))
        #expect(FileManager.default.fileExists(atPath: other.path), "someone else's file must stay")
    }

    @Test("a link, a tracking number and a phone number are opened as their URLs")
    func whenURLBased_thenOpenedDirectly() {
        let opened = Opened()
        EntityActionRunner.run(.trackingNumber(.ups, "1Z999AA10123456784"), open: { opened.add($0) })
        EntityActionRunner.run(.phoneNumber("(555) 123-4567"), open: { opened.add($0) })

        #expect(opened.all.map(\.scheme) == ["https", "tel"])
    }
}
