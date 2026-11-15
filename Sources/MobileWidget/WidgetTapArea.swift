// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import WidgetKit

/// Makes a card do its tap: a button that runs the in-place copy, or a link to the app. The small widget takes no
/// `Link`, so there the whole widget carries the link as its `widgetURL`.
struct WidgetTapArea<Content: View>: View {
    let tap: WidgetTap
    let isWholeWidget: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch tap {
        case let .copyInPlace(id):
            Button(intent: CopyClipIntent(clipID: id)) { content() }
                .buttonStyle(.plain)
        case let .link(url):
            if isWholeWidget {
                content().widgetURL(url)
            } else {
                Link(destination: url) { content() }
            }
        }
    }
}
