// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import WidgetKit

/// Makes a card do its tap: a button that runs the in-place copy (iOS only), or a link to the app. The small widget
/// takes no `Link`, so there the whole widget carries the link as its `widgetURL`. The Mac never copies in place (ADR
/// 0058): its copy is the app's, through the copy link.
struct WidgetTapArea<Content: View>: View {
    let tap: WidgetTap
    let isWholeWidget: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch tap {
        case let .copyInPlace(id):
            #if os(iOS)
            Button(intent: CopyClipIntent(clipID: id)) { content() }
                .buttonStyle(.plain)
            #else
            linked(WidgetLink.url(for: id))
            #endif
        case let .link(url):
            linked(url)
        }
    }

    @ViewBuilder
    private func linked(_ url: URL) -> some View {
        if isWholeWidget {
            content().widgetURL(url)
        } else {
            Link(destination: url) { content() }
        }
    }
}
