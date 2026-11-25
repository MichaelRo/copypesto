// SPDX-License-Identifier: MIT
import AppIntents
import Foundation
import PestoCore

/// The page buttons of a medium or large widget (ADR 0067): moves the page and lets WidgetKit draw the widget again.
/// It runs in the widget extension and touches only the extension's own page store; it reads no clip.
struct ShowClipPageIntent: AppIntent {
    static let title: LocalizedStringResource = "Show More Clips"
    static let isDiscoverable = false

    @Parameter(title: "Widget") var key: String
    @Parameter(title: "Step") var step: Int
    @Parameter(title: "Page") var page: Int
    @Parameter(title: "Pages") var pageCount: Int
    @Parameter(title: "Snapshot") var snapshotCreatedAt: Double

    init() {}

    init(key: String, step: Int, page: Int, pageCount: Int, snapshotCreatedAt: Date) {
        self.key = key
        self.step = step
        self.page = page
        self.pageCount = pageCount
        self.snapshotCreatedAt = snapshotCreatedAt.timeIntervalSinceReferenceDate
    }

    func perform() async throws -> some IntentResult {
        WidgetPageStore.save(
            page: WidgetPaging.step(from: page, by: step, pageCount: pageCount), for: key,
            snapshotCreatedAt: Date(timeIntervalSinceReferenceDate: snapshotCreatedAt), at: .now
        )
        return .result()
    }
}
