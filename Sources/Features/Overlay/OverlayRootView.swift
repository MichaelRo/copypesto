// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// The root SwiftUI view rendered inside `OverlayPanel`.
/// It hosts the glass shelf background, the CommandBar at top and the horizontal card GridView.
struct OverlayRootView: View {
    @Environment(AppState.self) var appState: AppState
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var focusedDominantColor: Color = .clear
    @State private var focusX: CGFloat = 0.5
    @AppStorage(Setting.accentColorHex) private var accentColorHex: String
    @AppStorage(Setting.appTheme) private var appThemeRaw: String
    @AppStorage(Setting.appThemeDark) private var appThemeDarkRaw: String

    private var axPermissionBanner: some View {
        Button {
            AccessibilityPermission.openSystemSettings()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.statusWarning)
                    .accessibilityHidden(true)
                Text("Accessibility access needed for auto-paste — click to fix")
                    .scaledFont(size: 11)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10))
                    .pestoQuiet()
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(bannerFill(.orange))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.accessibilityBanner)
    }

    /// At the default contrast a 10%-opacity tint is enough to read as a banner; under
    /// Increase Contrast it also gets a solid border, since low-opacity fills are exactly what that
    /// setting asks views to stop relying on alone.
    private func bannerFill(_ tint: Color) -> some View {
        ZStack {
            // A ground of its own under the tint: on bare glass the message read from 3:1 to 5:1 over the wallpaper
            // (the audit failed the Undo banner's text in light mode).
            Color.opaqueSurface
            tint.opacity(0.10)
            if contrast == .increased {
                Rectangle().strokeBorder(tint.opacity(0.6), lineWidth: 1)
            }
        }
    }

    private func userErrorBanner(_ message: String) -> some View {
        Button { appState.dismissUserError() } label: {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.statusBad)
                    .accessibilityHidden(true)
                Text(message)
                    .scaledFont(size: 11)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .pestoQuiet()
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 3)
            .background(bannerFill(.red))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { appState.holdUserError() } else { appState.releaseUserError() }
        }
        .accessibilityIdentifier(AccessibilityID.userErrorBanner)
    }

    /// A capsule in the band under the cards (where the selection bar floats), so a delete never covers a card's
    /// header.
    private func undoBanner(_ label: UndoLabel) -> some View {
        ShelfBannerCapsule(
            symbol: "arrow.uturn.backward.circle.fill",
            message: UndoText.action(label),
            primary: .init(title: "Undo (\u{2318}Z)", identifier: AccessibilityID.undoButton) {
                appState.performUndo()
            },
            onDismiss: { appState.dismissUndoOffer() }
        )
        .fixedSize()
        .onHover { hovering in
            if hovering { appState.holdUndoOffer() } else { appState.releaseUndoOffer() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.undoBanner)
    }

    private var clickHint: some View {
        Text("Return or a double-click pastes.")
            .scaledFont(size: 11)
            .pestoQuiet()
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(Capsule().fill(Color.opaqueSurface))
            .allowsHitTesting(false)
            .onAppear { appState.noteClickHintDrawn() }
            .accessibilityIdentifier(AccessibilityID.clickHint)
    }

    private func storageBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.statusWarning)
                .accessibilityHidden(true)
            Text(message)
                .scaledFont(size: 11)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(bannerFill(.orange))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.storageBanner)
    }

    /// One app starts its import; several are chosen from in Settings.
    private func importOfferButtonTitle(_ sources: [ImportSource]) -> LocalizedStringKey {
        if sources.count == 1 { return "Import\u{2026}" }
        return "Choose\u{2026}"
    }

    private func importOfferText(_ sources: [ImportSource]) -> String {
        let names = ImportOfferPolicy.bannerNames(for: sources)
        let parts = names.more > 0 ? names.shown + [String(localized: "\(names.more) more")] : names.shown
        return String(localized: "You have \(CountText.list(parts)). Bring your history into Pesto?")
    }

    private func importOfferBanner(_ sources: [ImportSource]) -> some View {
        ShelfBannerCapsule(
            symbol: "tray.and.arrow.down",
            message: importOfferText(sources),
            primary: .init(
                title: importOfferButtonTitle(sources), identifier: AccessibilityID.importOfferImportButton
            ) { appState.answerImportOffer(accepted: true) },
            secondary: .init(title: "Not Now", identifier: AccessibilityID.importOfferDismissButton) {
                appState.answerImportOffer(accepted: false)
            }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.importOfferBanner)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if let notice = StorageNotice.message(
                    hasStorage: appState.historyContainer != nil, isOnDisk: appState.storeIsOnDisk
                ) {
                    storageBanner(notice)
                }

                if !appState.hasAccessibilityPermission {
                    axPermissionBanner
                }

                if !appState.importOffer.isEmpty {
                    importOfferBanner(appState.importOffer)
                }

                CommandBarView()
                    .disabled(appState.isHistoryLocked)
                    .accessibilityHidden(appState.isHistoryLocked)
                    // The chips name apps and collections ("Notes"), so the locked shelf smears them like the cards
                    // (D-01).
                    .blur(radius: appState.isHistoryLocked ? ShelfLockCover.blurRadius : 0)
                    .padding(.horizontal, 16)
                    .padding(.top, appState.isSearchActive ? 6 : 12)
                    .padding(.bottom, appState.isSearchActive ? 2 : 8)

                BiometricLockOverlay {
                    GridView(
                        onFocusChanged: { dominantColor, normalizedX in
                            focusedDominantColor = dominantColor
                            focusX = normalizedX
                        }
                    )
                }
                // The error banner that comes and goes sits in the room above the cards (where a focused card lifts),
                // so
                // showing it does not move the toolbar and the cards under the pointer (D-03). The banners that stay
                // (storage, Accessibility, an import offer) keep their place in the layout above. The Undo offer is a
                // capsule under the cards and covers none of them.
                .overlay(alignment: .bottom) {
                    if let label = appState.undoOffer {
                        undoBanner(label)
                            .padding(.bottom, SelectionActionBar.bottomInset)
                            .transition(.opacity.combined(with: .offset(y: 8)))
                    } else if let presentation = appState.shelfSuggestion,
                              appState.importOffer.isEmpty,
                              !appState.isHistoryLocked,
                              !appState.isContentCovered(screenSharingPrivacy: AppDefaults.store
                                  .value(for: Setting.screenSharingPrivacy))
                    {
                        SuggestionBanner(presentation: presentation)
                            .padding(.horizontal, 16)
                            .padding(.bottom, SelectionActionBar.bottomInset)
                    } else if appState.isClickHintVisible {
                        clickHint
                            .padding(.bottom, SelectionActionBar.bottomInset)
                            .transition(.opacity)
                    }
                }
                .animation(Motion.animation(.pestoQuick), value: appState.isClickHintVisible)
                .overlay(alignment: .top) {
                    VStack(spacing: 0) {
                        if let message = appState.lastUserError { userErrorBanner(message) }
                    }
                    // Up into the 8 points the toolbar leaves under its chips, so a 28 point banner ends above the
                    // cards' headers instead of over them.
                    .offset(y: -8)
                }
            }
            .background(ShelfBackground(dominantColor: focusedDominantColor))
        }
        .ignoresSafeArea()
        // The panel is not exposed to accessibility as a window, so the root view carries the identifier.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clipboard history")
        .accessibilityIdentifier(AccessibilityID.overlayPanel)
        .pestoAccented(stored: accentColorHex, theme: appThemeRaw, darkTheme: appThemeDarkRaw)
        // Thread the synced SwiftData container so @Query in GridView has a ModelContext.
        .modelContainerIfAvailable(appState.historyContainer)
    }
}

// MARK: - Conditional model container injection

private extension View {
    @ViewBuilder
    func modelContainerIfAvailable(_ container: ModelContainer?) -> some View {
        if let container {
            self.modelContainer(container)
        } else {
            self
        }
    }
}
