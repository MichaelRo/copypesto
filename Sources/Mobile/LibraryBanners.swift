// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The banner under the content: Undo after a delete, otherwise the last thing done or refused.
struct LibraryBanners: View {
    var messagesOnly = false
    @Environment(MobileAppState.self) private var appState
    @AppStorage(Setting.dismissedAnnouncementIDs) private var dismissedAnnouncementsRaw: String

    var body: some View {
        Group {
            if appState.undoOffer != nil || appState.notice != nil {
                messages
            } else if !messagesOnly, appState.clipboardOfferCount != nil {
                ClipboardOfferBanner()
            } else if !messagesOnly, appState.offersAutoFillTip, !appState.isHistoryLocked {
                AutoFillTipBanner()
            } else if !messagesOnly,
                      let announcement = appState.activeAnnouncement(dismissedRaw: dismissedAnnouncementsRaw)
            {
                announcementBanner(announcement)
            }
        }
        .animation(Motion.animation(.pestoMove), value: appState.clipboardOfferCount)
        .animation(Motion.animation(.pestoMove), value: appState.offersAutoFillTip)
    }

    private func announcementBanner(_ announcement: AppAnnouncement) -> some View {
        banner {
            Image(systemName: announcement.symbol)
                .accessibilityHidden(true)
            Text(announcement.message)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button(announcement.primaryTitle) {
                appState.openAnnouncement(announcement)
            }
            .bold()
            .frame(minWidth: TouchTarget.minimum, minHeight: TouchTarget.minimum)
            .contentShape(.rect)
            .padding(.vertical, -12)
            .accessibilityIdentifier(MobileAccessibilityID.announcementPrimaryButton)
            Button(announcement.secondaryTitle) {
                appState.dismissAnnouncement(announcement)
            }
            .foregroundStyle(.secondary)
            .frame(minWidth: TouchTarget.minimum, minHeight: TouchTarget.minimum)
            .contentShape(.rect)
            .padding(.vertical, -12)
            .accessibilityIdentifier(MobileAccessibilityID.announcementDismissButton)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(MobileAccessibilityID.announcementBanner)
    }

    private var messages: some View {
        Group {
            if let label = appState.undoOffer {
                banner {
                    Text(UndoOfferText.action(label))
                    Spacer(minLength: 8)
                    Button("Undo") { Task { await appState.undo() } }
                        .bold()
                        .frame(minWidth: TouchTarget.minimum, minHeight: TouchTarget.minimum)
                        .contentShape(.rect)
                        .padding(.vertical, -12)
                        .accessibilityIdentifier(MobileAccessibilityID.undoButton)
                }
            } else if let notice = appState.notice {
                banner {
                    Image(systemName: notice.isProblem ? "exclamationmark.circle" : "checkmark.circle")
                        .accessibilityHidden(true)
                    Text(notice.text)
                    if notice.isProblem { Spacer(minLength: 0) }
                }
                .fixedSize(horizontal: !notice.isProblem && notice.text.count < 36, vertical: false)
                .multilineTextAlignment(.leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(MobileAccessibilityID.noticeBanner)
            }
        }
        .animation(Motion.animation(.pestoMove), value: appState.undoOffer)
        .animation(Motion.animation(.pestoMove), value: appState.notice)
    }

    private func banner(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 10) { content() }
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .mobileGlassChrome(in: .capsule, interactive: true)
            .frame(maxWidth: 560)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

extension View {
    /// Once per screen: on each compact tab's stack, and over the whole split view on iPad.
    func libraryBanners() -> some View {
        overlay(alignment: .bottom) { LibraryBanners() }
    }
}
