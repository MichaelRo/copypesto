// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

struct ShelfEmptyStateView: View {
    let state: ShelfEmptyState
    let query: String
    var onAction: ((ShelfEmptyState.Action) -> Void)?

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
            "Nothing matches “\(query)”. Search reads the first 500 characters of each clip."
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
