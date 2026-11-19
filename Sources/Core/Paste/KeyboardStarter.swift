// SPDX-License-Identifier: MIT
import Foundation

/// A key on Pesto's keyboard that inserts a value made at the moment of the tap (ADR 0061). It needs no clip, so it
/// works without Full Access, when the keyboard cannot open the quick-insert set.
public enum KeyboardStarter: String, CaseIterable, Identifiable, Sendable {
    case date
    case time
    case isoDate
    case weekday
    case uuid

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
        case .date: String(localized: "Date")
        case .time: String(localized: "Time")
        case .isoDate: String(localized: "ISO Date")
        case .weekday: String(localized: "Weekday")
        case .uuid: String(localized: "UUID")
        }
    }

    private var placeholder: String {
        switch self {
        case .date: "{{date}}"
        case .time: "{{time}}"
        case .isoDate: "{{isodate}}"
        case .weekday: "{{weekday}}"
        case .uuid: "{{uuid}}"
        }
    }

    public func text(at date: Date = .now) -> String {
        TemplateExpander.expansion(of: placeholder, isSnippet: true, at: date, clipboardProvider: { "" }) ?? ""
    }
}
