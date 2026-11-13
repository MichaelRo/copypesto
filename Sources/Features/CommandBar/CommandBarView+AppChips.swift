// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

extension CommandBarView {
    var appChips: [SourceApp] {
        AppChipsRow.chips(recent: suggestionsModel.suggestions.recentApps, frontmost: suggestionsModel.frontmost)
    }

    static let allChipID = AnyHashable("all-collections")
    static let creatorID = AnyHashable("new-collection-creator")
    /// A point added to the measured width of the collection chips: a fractional width rounded down would clip the last
    /// chip's edge and make the row scroll for nothing.
    static let scrollSlack: CGFloat = 1

    func scrollToSelection(_ proxy: ScrollViewProxy) {
        let id = appState.selectedCollectionID
        guard id == nil || pinboards.contains(where: { $0.id == id }) else { return }
        scroll(to: id.map { AnyHashable($0) } ?? Self.allChipID, in: proxy, anchor: .center)
    }

    func scroll(to id: AnyHashable, in proxy: ScrollViewProxy, anchor: UnitPoint) {
        withAnimation(Motion.animation(.pestoMove)) { proxy.scrollTo(id, anchor: anchor) }
    }

    /// Outside the scroll view, right after it, so the apps stay in reach however many collections push the row past
    /// the bar.
    var pinnedAppChips: some View {
        HStack(spacing: 6) {
            Divider()
                .frame(height: 14)
                .padding(.horizontal, 2)
            AppChipsRow(
                recent: suggestionsModel.suggestions.recentApps, frontmost: suggestionsModel.frontmost,
                collapsesLabels: !shownPinboards.isEmpty
            )
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.leading, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("App filters")
    }

    var chipsRow: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    scrollableChips
                        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width in
                            // The first measurement is placed as is; later ones (the creator opening) glide.
                            if chipsContentWidth == nil {
                                chipsContentWidth = width
                            } else {
                                withAnimation(Motion.animation(.pestoMove)) { chipsContentWidth = width }
                            }
                        }
                }
                .layoutPriority(1)
                // Hugs its chips so the app chips sit right after the last collection, and only scrolls (with the app
                // chips held at the bar's end) once the collections run past the room there is.
                .frame(maxWidth: chipsContentWidth.map { $0 + Self.scrollSlack } ?? .infinity, alignment: .leading)
                .accessibilityLabel("Collections")
                .onChange(of: appState.selectedCollectionID) { scrollToSelection(proxy) }
                // A new collection is selected before the query has its chip, so look again once it has arrived.
                .onChange(of: pinboards.map(\.id)) { scrollToSelection(proxy) }
                .onChange(of: appState.isCreatingCollection) { _, creating in
                    if creating { scroll(to: Self.creatorID, in: proxy, anchor: .trailing) }
                }
            }
            if !appChips.isEmpty {
                pinnedAppChips
            }
            Spacer(minLength: 0)
            rightToolbar
        }
    }
}
