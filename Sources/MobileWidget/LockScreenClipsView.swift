// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import WidgetKit

/// Renders Pesto's accessory-family Lock Screen widgets in vibrant monochrome, never showing clip content until
/// `showsClipsOnLockScreen` is turned on in the widget's configuration (ADR 0065).
struct LockScreenClipsView: View {
    let entry: LockScreenClipsEntry
    /// Set by rendering tests where WidgetKit's family environment is absent.
    var familyOverride: WidgetFamily?
    @Environment(\.widgetFamily) private var family
    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.layoutDirection) private var layoutDirection

    private var resolvedFamily: WidgetFamily {
        familyOverride ?? family
    }

    private var isPrivacyRedacted: Bool {
        redactionReasons.contains(.privacy)
    }

    private var content: LockScreenWidgetContent {
        LockScreenWidgetContent(
            snapshot: entry.snapshot,
            showsClipsOnLockScreen: entry.showsClipsOnLockScreen,
            source: entry.source,
            action: entry.action,
            now: entry.date
        )
    }

    var body: some View {
        let model = content
        Group {
            switch resolvedFamily {
            case .accessoryCircular:
                circularBody(model)
            case .accessoryInline:
                inlineBody(model)
            default:
                rectangularBody(model)
            }
        }
        .widgetURL(model.tapURL)
        .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private func circularBody(_ model: LockScreenWidgetContent) -> some View {
        if case let .clip(clip) = model.state {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: clip.kind.presentation.symbolName)
                    .font(.title3.weight(.semibold))
                    .widgetAccentable()
            }
            .privacySensitive()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(clipVoiceOverLabel(clip))
            .accessibilityHint(clipVoiceOverHint)
        } else {
            let notice = message(for: model)
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: notice.symbol)
                    .font(.title3.weight(.semibold))
                    .widgetAccentable()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(notice.title). \(notice.detail)")
            .accessibilityHint(noticeHint(for: model))
        }
    }

    @ViewBuilder
    private func rectangularBody(_ model: LockScreenWidgetContent) -> some View {
        if case let .clip(clip) = model.state {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: clip.kind.presentation.symbolName)
                        .widgetAccentable()
                    Text(footText(clip))
                        .lineLimit(1)
                    if clip.isPinned {
                        Image(systemName: "pin.fill")
                            .widgetAccentable()
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                Text(displayText(for: clip, singleLine: false))
                    .font(clip.kind == .code ? .caption.monospaced() : .headline)
                    .lineLimit(2)
                    .environment(\.layoutDirection, forcesLTR(clip) ? .leftToRight : layoutDirection)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .privacySensitive()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(clipVoiceOverLabel(clip))
            .accessibilityHint(clipVoiceOverHint)
        } else {
            let notice = message(for: model)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: notice.symbol)
                        .widgetAccentable()
                        .accessibilityHidden(true)
                    Text(notice.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Text(notice.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityHint(noticeHint(for: model))
        }
    }

    @ViewBuilder
    private func inlineBody(_ model: LockScreenWidgetContent) -> some View {
        if case let .clip(clip) = model.state {
            Label(displayText(for: clip, singleLine: true), systemImage: clip.kind.presentation.symbolName)
                .privacySensitive()
                .accessibilityLabel(clipVoiceOverLabel(clip))
                .accessibilityHint(clipVoiceOverHint)
        } else {
            let notice = message(for: model)
            Label(notice.inlineText, systemImage: notice.symbol)
                .accessibilityHint(noticeHint(for: model))
        }
    }

    private func clipVoiceOverLabel(_ clip: WidgetClip) -> String {
        isPrivacyRedacted
            ? String(localized: "Hidden clip")
            : WidgetClipSpeech.label(clip, now: entry.date)
    }

    private var clipVoiceOverHint: String {
        isPrivacyRedacted ? "" : String(localized: "Opens this clip in Pesto")
    }

    private func noticeHint(for model: LockScreenWidgetContent) -> String {
        model.state == .locked ? String(localized: "Opens Pesto to unlock") : ""
    }

    private func forcesLTR(_ clip: WidgetClip) -> Bool {
        clip.kind == .code || clip.kind == .color
    }

    private func footText(_ clip: WidgetClip) -> String {
        let foot = WidgetClipSpeech.foot(clip, now: entry.date)
        return foot.isEmpty ? String(localized: "Pesto") : foot
    }

    private func displayText(for clip: WidgetClip, singleLine: Bool) -> String {
        let raw: String = switch clip.kind {
        case .url:
            clip.linkHost ?? clip.text
        case .color:
            clip.colorHex.map { "#\($0)" } ?? clip.text
        case .image:
            clip.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(localized: "Picture") : clip.text
        case .file:
            clip.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(localized: "File") : clip.text
        case .text, .code:
            clip.text
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard singleLine else { return trimmed }
        return trimmed
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private struct Notice {
        let symbol: String
        let title: String
        let detail: String
        let inlineText: String
    }

    private func message(for model: LockScreenWidgetContent) -> Notice {
        switch model.state {
        case .optInRequired:
            Notice(
                symbol: "eye.slash",
                title: String(localized: "Hidden on Lock Screen"),
                detail: String(localized: "Edit widget to show clips"),
                inlineText: String(localized: "Pesto Hidden")
            )
        case .locked:
            Notice(
                symbol: "lock.fill",
                title: String(localized: "Locked"),
                detail: String(localized: "Open Pesto to unlock"),
                inlineText: String(localized: "Pesto Locked")
            )
        case .unavailable:
            Notice(
                symbol: "doc.on.clipboard",
                title: String(localized: "Open Pesto"),
                detail: String(localized: "Open Pesto to show clips"),
                inlineText: String(localized: "Open Pesto")
            )
        case .hidden:
            Notice(
                symbol: "eye.slash",
                title: String(localized: "Contents hidden"),
                detail: String(localized: "Open Pesto to view"),
                inlineText: String(localized: "Contents hidden")
            )
        case .noCollection:
            Notice(
                symbol: "square.stack",
                title: String(localized: "Choose a collection"),
                detail: String(localized: "Edit widget to pick one"),
                inlineText: String(localized: "Choose a collection")
            )
        case .empty, .clip:
            if model.source == .pinned, model.collection == nil {
                Notice(
                    symbol: "pin",
                    title: String(localized: "No pinned clips yet"),
                    detail: String(localized: "Pin a clip in Pesto"),
                    inlineText: String(localized: "No pinned clips yet")
                )
            } else {
                Notice(
                    symbol: model.collection?.symbolName ?? "doc.on.clipboard",
                    title: String(localized: "No clips yet"),
                    detail: String(localized: "Add a clip in Pesto"),
                    inlineText: String(localized: "No clips yet")
                )
            }
        }
    }
}
