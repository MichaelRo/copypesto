// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The banner under the content: Undo after a delete, otherwise the last thing done or refused.
struct LibraryBanners: View {
    @Environment(MobileAppState.self) private var appState

    var body: some View {
        Group {
            if let label = appState.undoOffer {
                banner {
                    Text(UndoOfferText.action(label))
                    Spacer(minLength: 8)
                    Button("Undo") { Task { await appState.undo() } }
                        .bold()
                        .accessibilityIdentifier(MobileAccessibilityID.undoButton)
                }
            } else if let notice = appState.notice {
                banner {
                    Image(systemName: notice.isProblem ? "exclamationmark.circle" : "checkmark.circle")
                        .accessibilityHidden(true)
                    Text(notice.text)
                    if notice.isProblem { Spacer(minLength: 0) }
                }
                .fixedSize(horizontal: !notice.isProblem, vertical: false)
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
            .background(.regularMaterial, in: .capsule)
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
