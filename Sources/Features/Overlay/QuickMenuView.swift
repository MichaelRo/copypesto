// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftData
import SwiftUI

/// Compact 5-item horizontal grid shown at the cursor position when ⌘⇧V is pressed
/// inside a focused text field. Same card component as the main overlay — no command
/// bar, no multi-select.
struct QuickMenuView: View {
    @Query private var items: [ClipboardItem]
    @Environment(AppState.self) private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @AppStorage(Setting.screenSharingPrivacy) private var screenSharingPrivacy: Bool

    /// Called with the payload kind when the user selects an item.
    var onSelect: ((PasteCoordinator.PayloadKind) -> Void)?
    var onDismiss: (() -> Void)?

    init(onSelect: ((PasteCoordinator.PayloadKind) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.onSelect = onSelect
        self.onDismiss = onDismiss
        _items = Query(Self.descriptor(hidesSensitive: NSFWMode.current().hidesFromGrid))
    }

    /// Five clips, newest first, with the shelf's rule that clips hidden as sensitive stay out of sight.
    nonisolated static func descriptor(hidesSensitive: Bool) -> FetchDescriptor<ClipboardItem> {
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: hidesSensitive ? #Predicate { !$0.isNSFW } : nil,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 5
        return descriptor
    }

    private var displayItems: [ClipboardItem] {
        items
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            cardRow
                .padding(.horizontal, QuickMenuMetrics.horizontalPadding)
                .padding(.vertical, QuickMenuMetrics.verticalPadding)
        }
        .adaptiveMaterialBackground()
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            // Glass cards provide their own edge highlights, so this border is only
            // needed as a container outline when glass is unavailable.
            if #unavailable(macOS 26) {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
        .accessibilityElement(children: .contain)
        // Needs a label of its own, as the AppKit panel has in QuickMenuWindowController.
        .accessibilityLabel("Quick menu")
        .accessibilityIdentifier(AccessibilityID.quickMenuPanel)
    }

    @ViewBuilder
    private var cardRow: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer {
                cardHStack
            }
        } else {
            cardHStack
        }
    }

    private var cardHStack: some View {
        LazyHStack(spacing: QuickMenuMetrics.spacing) {
            ForEach(displayItems) { item in
                ClipboardCard(
                    item: item,
                    isFocused: false,
                    isPrivacyBlurred: appState.isContentCovered(screenSharingPrivacy: screenSharingPrivacy)
                )
            }
        }
        // A menu, not a list: one click pastes (the second click of a double does nothing more).
        .environment(\.cardActions, CardActions(click: { item, click in
            if click != .double { selectItem(item) }
        }))
    }

    private func selectItem(_ item: ClipboardItem) {
        guard let payloadKind = appState.writeItem(item) else {
            onDismiss?()
            return
        }
        appState.notePasted(item, in: modelContext)
        onSelect?(payloadKind)
        onDismiss?()
    }
}
