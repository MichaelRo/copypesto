// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// The pages widgets show, in the widget extension's own preferences (ADR 0067): a page number and two dates per
/// key, never any content.
enum WidgetPageStore {
    static func page(
        for key: String, snapshotCreatedAt: Date, pageCount: Int, now: Date,
        in defaults: UserDefaults = AppDefaults.store
    )
    -> Int {
        let pages = WidgetPaging.Pages(text: defaults.value(for: Setting.widgetPages))
        return WidgetPaging.page(
            stored: pages[key], snapshotCreatedAt: snapshotCreatedAt, pageCount: pageCount, now: now
        )
    }

    /// When the page set for `key` goes back to the first, if it is past the first.
    static func resetMoment(for key: String, in defaults: UserDefaults = AppDefaults.store) -> Date? {
        let pages = WidgetPaging.Pages(text: defaults.value(for: Setting.widgetPages))
        guard let stored = pages[key], stored.page > 0 else { return nil }
        return stored.setAt + WidgetPaging.timeout
    }

    static func save(
        page: Int, for key: String, snapshotCreatedAt: Date, at now: Date,
        in defaults: UserDefaults = AppDefaults.store
    ) {
        var pages = WidgetPaging.Pages(text: defaults.value(for: Setting.widgetPages))
        pages[key] = WidgetPaging.Stored(page: page, setAt: now, snapshotCreatedAt: snapshotCreatedAt)
        defaults.set(pages.text, for: Setting.widgetPages)
    }
}
