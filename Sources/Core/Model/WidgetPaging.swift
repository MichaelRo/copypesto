// SPDX-License-Identifier: MIT
import Foundation

/// Which page a medium or large widget shows (ADR 0067). WidgetKit cannot scroll, so a button advances a page that is
/// kept in the widget extension's own preferences (`Setting.widgetPages`, never read by the app) under a key of the
/// family and the list it shows; two widgets showing the same list in the same family page together. A page goes back
/// to the first when a newer snapshot arrives or after `timeout`, so a widget does not stay on page three for good.
public enum WidgetPaging {
    public static let timeout: TimeInterval = 600

    public struct Stored: Codable, Equatable, Sendable {
        public let page: Int
        public let setAt: Date
        public let snapshotCreatedAt: Date

        public init(page: Int, setAt: Date, snapshotCreatedAt: Date) {
            self.page = page
            self.setAt = setAt
            self.snapshotCreatedAt = snapshotCreatedAt
        }
    }

    /// The stored pages by key, kept as one JSON text in the extension's preferences.
    public struct Pages: Equatable, Sendable {
        private var byKey: [String: Stored]

        public init() {
            byKey = [:]
        }

        public init(text: String) {
            byKey = (try? JSONDecoder().decode([String: Stored].self, from: Data(text.utf8))) ?? [:]
        }

        public var text: String {
            guard let data = try? JSONEncoder().encode(byKey) else { return "" }
            return String(bytes: data, encoding: .utf8) ?? ""
        }

        public subscript(key: String) -> Stored? {
            get { byKey[key] }
            set { byKey[key] = newValue }
        }
    }

    public static func key(source: WidgetClipSource, size: WidgetSize) -> String {
        let list = switch source {
        case .recent: "recent"
        case .pinned: "pinned"
        case let .collection(id): "collection:\(id?.uuidString ?? "none")"
        }
        return "\(list)|\(size)"
    }

    public static func page(stored: Stored?, snapshotCreatedAt: Date, pageCount: Int, now: Date) -> Int {
        // The date crosses an App Intent parameter as a Double, which can come back a fraction of a microsecond early.
        guard let stored, stored.snapshotCreatedAt.timeIntervalSince(snapshotCreatedAt) > -0.001,
              now.timeIntervalSince(stored.setAt) < timeout else { return 0 }
        return min(max(stored.page, 0), max(pageCount - 1, 0))
    }

    public static func step(from page: Int, by delta: Int, pageCount: Int) -> Int {
        guard pageCount > 1 else { return 0 }
        return ((page + delta) % pageCount + pageCount) % pageCount
    }
}
