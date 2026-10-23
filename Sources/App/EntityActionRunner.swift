// SPDX-License-Identifier: MIT
import AppKit
import PestoCore

/// Carries out a detected action from a card's "Open With" menu. A date becomes a calendar file that is opened, so the
/// user's calendar app asks what to do and Pesto needs no calendar permission.
@MainActor
enum EntityActionRunner {
    static func run(
        _ entity: EntityDetector.Entity,
        removeAfter delay: Duration = .seconds(120),
        open: (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        if case let .date(details) = entity {
            let ics = ICalendarEvent.make(title: details.title, start: details.start, hasTime: details.hasTime)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("Pesto event \(UUID().uuidString.prefix(8)).ics")
            guard (try? ics.write(to: url, atomically: true, encoding: .utf8)) != nil else { return }
            open(url)
            // The file holds the copied text; the calendar app has read it long before this.
            Task {
                try? await Task.sleep(for: delay)
                try? FileManager.default.removeItem(at: url)
            }
        } else if let url = entity.actionURL {
            open(url)
        }
    }
}
