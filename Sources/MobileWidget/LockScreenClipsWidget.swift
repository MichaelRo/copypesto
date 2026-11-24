// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftUI
import WidgetKit

struct LockScreenClipsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var showsClipsOnLockScreen = false
    var source: WidgetClipSource = .recent
    var action: LockScreenWidgetContent.Action = .copy
}

struct LockScreenClipsProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> LockScreenClipsEntry {
        LockScreenClipsEntry(date: .now, snapshot: nil, showsClipsOnLockScreen: false)
    }

    func snapshot(for configuration: LockScreenClipsConfiguration, in context: Context) async -> LockScreenClipsEntry {
        let snapshot = (!context.isPreview && configuration.showsClipsOnLockScreen)
            ? WidgetSnapshotReader.read()
            : nil
        return LockScreenClipsEntry(
            date: .now,
            snapshot: snapshot,
            showsClipsOnLockScreen: configuration.showsClipsOnLockScreen,
            source: configuration.clipSource,
            action: configuration.clipAction
        )
    }

    func timeline(
        for configuration: LockScreenClipsConfiguration,
        in _: Context
    ) async
        -> Timeline<LockScreenClipsEntry>
    {
        Self.timeline(
            snapshot: configuration.showsClipsOnLockScreen ? WidgetSnapshotReader.read() : nil,
            now: .now,
            showsClipsOnLockScreen: configuration.showsClipsOnLockScreen,
            source: configuration.clipSource,
            action: configuration.clipAction
        )
    }

    static func timeline(
        snapshot: WidgetSnapshot?,
        now: Date,
        showsClipsOnLockScreen: Bool = false,
        source: WidgetClipSource = .recent,
        action: LockScreenWidgetContent.Action = .copy
    )
        -> Timeline<LockScreenClipsEntry>
    {
        let content = LockScreenWidgetContent(
            snapshot: snapshot,
            showsClipsOnLockScreen: showsClipsOnLockScreen,
            source: source,
            action: action,
            now: now
        )
        var moments: [Date] = if case let .clip(clip) = content.state {
            WidgetContent.refreshDates(for: [clip], after: now)
        } else {
            []
        }
        if showsClipsOnLockScreen, let expiresAt = snapshot?.expiresAt, expiresAt > now {
            moments = Array(Set(moments.filter { $0 < expiresAt } + [expiresAt]).sorted())
        }
        func entry(_ date: Date) -> LockScreenClipsEntry {
            LockScreenClipsEntry(
                date: date,
                snapshot: snapshot,
                showsClipsOnLockScreen: showsClipsOnLockScreen,
                source: source,
                action: action
            )
        }
        return Timeline(entries: [entry(now)] + moments.map(entry), policy: moments.isEmpty ? .never : .atEnd)
    }
}

/// Lock Screen accessory widget (ADR 0065): circular, rectangular, and inline views gated by per-widget opt-in.
struct LockScreenClipsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: AppIdentity.lockScreenWidgetKind,
            intent: LockScreenClipsConfiguration.self,
            provider: LockScreenClipsProvider()
        ) { entry in
            LockScreenClipsView(entry: entry)
        }
        .configurationDisplayName("Lock Screen Clips")
        .description(
            "Show your latest clip on the Lock Screen when turned on in widget settings. Secrets never appear."
        )
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
