// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

struct SuggestionBanner: View {
    let presentation: ShelfSuggestionPresentation
    @Environment(\.pestoAccent) private var accent
    @Environment(AppState.self) private var appState: AppState

    private var symbol: String {
        if presentation.isNotice { return "info.circle" }
        switch presentation.suggestion {
        case .shortcutOffer, .shortcutReminder, .shortcutRelease: return "keyboard"
        case .snippet: return "curlybraces"
        case nil: return "info.circle"
        }
    }

    private var titleText: String {
        if presentation.isNotice { return ShelfSuggestionCopy.offNoticeTitle }
        guard let suggestion = presentation.suggestion else { return "" }
        switch suggestion {
        case let .shortcutOffer(_, slot, pasteCount, isPinned):
            return ShelfSuggestionCopy.shortcutOfferTitle(
                pasteCount: pasteCount,
                keyString: "⌃\(slot)",
                isPinned: isPinned
            )
        case let .shortcutReminder(_, slot):
            return ShelfSuggestionCopy.reminderTitle(shelfPastes: 5, keyString: "⌃\(slot)")
        case let .shortcutRelease(_, slot, weeks):
            return ShelfSuggestionCopy.dormantTitle(keyString: "⌃\(slot)", weeks: weeks)
        case .snippet:
            return ShelfSuggestionCopy.snippetTitle()
        }
    }

    private var primaryTitle: LocalizedStringKey {
        if presentation.isNotice { return "Settings" }
        guard let suggestion = presentation.suggestion else { return "" }
        switch suggestion {
        case let .shortcutOffer(_, slot, _, isPinned):
            return isPinned ? "Use ⌃\(slot)" : "Pin with ⌃\(slot)"
        case .shortcutReminder:
            return "Got It"
        case .shortcutRelease:
            return "Remove Shortcut"
        case .snippet:
            return "Make Snippet\u{2026}"
        }
    }

    private var secondaryTitle: LocalizedStringKey? {
        if presentation.isNotice { return "Dismiss" }
        guard let suggestion = presentation.suggestion else { return nil }
        switch suggestion {
        case .shortcutOffer, .snippet:
            return "No Thanks"
        case .shortcutRelease:
            return "Keep Shortcut"
        case .shortcutReminder:
            return nil
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text(titleText)
                .lineLimit(2)
                .scaledFont(size: 11)
                .foregroundStyle(.primary)
                .help(titleText)
            Spacer()
            Button(primaryTitle) {
                if presentation.isNotice {
                    appState.pendingSettingsSection = SettingsSection.general.rawValue
                    appState.openSettingsFromOverlay?()
                    appState.shelfSuggestion = nil
                } else {
                    appState.acceptShelfSuggestion()
                }
            }
            .buttonStyle(.pestoCapsule(.primary))
            .accessibilityIdentifier(AccessibilityID.shelfSuggestionAcceptButton)

            if let secondaryTitle {
                Button(secondaryTitle) {
                    if presentation.isNotice {
                        appState.shelfSuggestion = nil
                    } else {
                        appState.declineShelfSuggestion()
                    }
                }
                .buttonStyle(.pestoCapsule(.secondary))
                .accessibilityIdentifier(AccessibilityID.shelfSuggestionDeclineButton)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(BannerFill(tint: accent))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(titleText)
        .accessibilityIdentifier(AccessibilityID.shelfSuggestionBanner)
    }
}
