// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// Which tile copied in place last, and when, in the widget extension's own preferences: an id and a time, never any
/// content, so the next timeline shows that tile as Copied for a moment.
enum WidgetCopyRecord {
    static func save(_ id: UUID, at date: Date, in defaults: UserDefaults = AppDefaults.store) {
        defaults.set("\(id.uuidString)@\(date.timeIntervalSince1970)", for: Setting.widgetLastCopy)
    }

    /// The clip copied within `WidgetSnapshotPolicy.copiedFeedback` before `now`, and when it was copied.
    static func recent(at now: Date, in defaults: UserDefaults = AppDefaults.store) -> (id: UUID, date: Date)? {
        let parts = defaults.value(for: Setting.widgetLastCopy).split(separator: "@")
        guard parts.count == 2, let id = UUID(uuidString: String(parts[0])),
              let seconds = TimeInterval(parts[1]) else { return nil }
        let date = Date(timeIntervalSince1970: seconds)
        let age = now.timeIntervalSince(date)
        guard age >= 0, age < WidgetSnapshotPolicy.copiedFeedback else { return nil }
        return (id, date)
    }
}
