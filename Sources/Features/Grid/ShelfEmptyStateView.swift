// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

struct ShelfEmptyStateView: View {
    let state: ShelfEmptyState
    let query: String
    var advice: NoResultsAdvice?
    var hasKeyboardCursor = false
    var onAction: ((ShelfEmptyState.Action) -> Void)?
    var onAdvice: ((NoResultsAdvice.Action) -> Void)?
    /// Ask Pesto is offered on No results, first when the search reads like a question (as on the iPhone), where
    /// Return asks too.
    var asksFirst = false
    var onAsk: (() -> Void)?
    @Environment(\.pestoAccent) private var accent

    var body: some View {
        VStack(spacing: 6) {
            Image(illustration)
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: state == .noResults ? 96 : 120)
                .settleOnAppear(.sway)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.callout)
                .pestoQuiet()
                .multilineTextAlignment(.center)
            if let action = state.action {
                Button(actionTitle(action)) { onAction?(action) }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .padding(.top, 6)
                    .accessibilityIdentifier(AccessibilityID.shelfEmptyStateAction)
            }
            if advice != nil || onAsk != nil {
                HStack(spacing: 8) {
                    if asksFirst { askButton(prominent: true) }
                    if let advice { adviceButton(advice) }
                    if !asksFirst { askButton(prominent: false) }
                }
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        // Its own ground: the captions used to sit on bare glass over whatever wallpaper was behind (4.1 to 4.4:1).
        .adaptiveMaterialBackground()
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: 420)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.shelfEmptyState)
    }

    @ViewBuilder
    private func adviceButton(_ advice: NoResultsAdvice) -> some View {
        let button = Button(advice.buttonTitle) { onAdvice?(advice.action) }
            .controlSize(.regular)
            .overlay(Capsule().strokeBorder(accent, lineWidth: hasKeyboardCursor ? 2 : 0).padding(-2))
            .help(advice.buttonTitle)
            .accessibilityIdentifier(AccessibilityID.shelfEmptyStateAdvice)
        if asksFirst { button.buttonStyle(.bordered) } else { button.buttonStyle(.pestoProminent) }
    }

    @ViewBuilder
    private func askButton(prominent: Bool) -> some View {
        if let onAsk {
            let button = Button("Ask Pesto", systemImage: "sparkles", action: onAsk)
                .controlSize(.regular)
                .help("Turn this into filters (⌘Return)")
                .accessibilityIdentifier(AccessibilityID.shelfEmptyStateAsk)
            if prominent { button.buttonStyle(.pestoProminent) } else { button.buttonStyle(.bordered) }
        }
    }

    private func actionTitle(_ action: ShelfEmptyState.Action) -> LocalizedStringKey {
        switch action {
        case .openPrivacySettings: "Open Privacy Settings"
        case .resumeCapturing: "Resume Capturing"
        }
    }

    private var illustration: String {
        switch state {
        case .storageUnavailable: "IllustrationUnavailable"
        case .noResults: "IllustrationNoResults"
        case .emptyCollection, .noClips, .emptyAppFilter: "IllustrationNoClips"
        case .captureBlocked: "IllustrationBlocked"
        case .paused: "IllustrationPaused"
        }
    }

    private var title: String {
        switch state {
        case .storageUnavailable: "History is unavailable"
        case .noResults: "No results"
        case .emptyCollection: "This collection is empty"
        case let .emptyAppFilter(name): "No clips from \(name)"
        case .captureBlocked: "Clipboard access is blocked"
        case .paused: "Capturing is paused"
        case .noClips: "Nothing copied yet"
        }
    }

    private var detail: String {
        switch state {
        case .storageUnavailable:
            "Pesto couldn’t open its history. Restart Pesto, and check free disk space if it happens again."
        case .noResults:
            asksFirst
                ? String(localized: "Press Return to ask Pesto to turn this into filters.")
                : advice?.sentence ?? NoResultsAdvice.make(query: query).sentence
        case .emptyCollection:
            "Drag a clip onto the collection to add it."
        case let .emptyAppFilter(name):
            "Clips you copy while using \(name) will appear here."
        case .captureBlocked:
            "Allow “Paste from Other Apps” for Pesto in System Settings → Privacy & Security."
        case .paused:
            "Resume from the menu bar icon to record new copies."
        case .noClips:
            "A clean jar. Copy something and it appears here. Press Return or double-click a clip to paste it."
        }
    }
}
