// SPDX-License-Identifier: MIT
import Foundation

/// What a Lock Screen accessory widget may show from the sealed snapshot (ADR 0065): nothing until the person
/// turns on "Show Clips on Lock Screen" on that widget (`optInRequired`), then at most one eligible clip (or Locked /
/// Empty / Unavailable). Secrets never enter the snapshot and are never shown.
public struct LockScreenWidgetContent: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case optInRequired
        case unavailable
        case locked
        case hidden
        case noCollection
        case empty
        case clip(WidgetClip)
    }

    public enum Action: String, CaseIterable, Codable, Equatable, Sendable {
        case copy
        case openPesto
        case openClip
    }

    public let state: State
    public let action: Action
    public let source: WidgetClipSource
    public let collection: WidgetCollection?
    public let tapURL: URL?

    public init(
        snapshot: WidgetSnapshot?, showsClipsOnLockScreen: Bool, source: WidgetClipSource = .recent,
        action: Action = .copy, now: Date = .now
    ) {
        self.action = action
        self.source = source
        guard showsClipsOnLockScreen else {
            state = .optInRequired
            collection = nil
            tapURL = nil
            return
        }
        let widget = WidgetContent(snapshot: snapshot, size: .small, source: source, now: now)
        collection = widget.collection
        switch widget.state {
        case .unavailable:
            state = .unavailable
            tapURL = nil
        case .locked:
            state = .locked
            tapURL = AppLink.url(for: .unlock)
        case .hidden:
            state = .hidden
            tapURL = nil
        case .noCollection:
            state = .noCollection
            tapURL = nil
        case .empty:
            state = .empty
            tapURL = nil
        case .clips:
            if let first = widget.clips.first {
                state = .clip(first)
                tapURL = switch action {
                case .copy: WidgetLink.url(for: first.id)
                case .openPesto: nil
                case .openClip: WidgetLink.url(for: first.id, action: .show)
                }
            } else {
                state = .empty
                tapURL = nil
            }
        }
    }
}
