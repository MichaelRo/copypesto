// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// What every step has in common: the art (hidden at accessibility sizes), the title that says which step this is to
/// VoiceOver, the line under it, then the step's own content, all in a scroll view above the pinned buttons.
struct WelcomePage<Art: View, Content: View>: View {
    let stepNumber: Int
    let title: String
    let line: String
    @ViewBuilder var art: Art
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    if !typeSize.isAccessibilitySize {
                        art.frame(maxWidth: 340).padding(.bottom, 4)
                    }
                    VStack(spacing: 10) {
                        Text(title)
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                            .accessibilityLabel(Text("Step \(stepNumber) of \(WelcomeModel.stepCount). \(title)"))
                            .accessibilityAddTraits(.isHeader)
                        Text(line)
                            .font(.body)
                            .pestoQuiet()
                            .multilineTextAlignment(.center)
                    }
                    content
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

struct WelcomeRow: View {
    let symbol: String
    let title: LocalizedStringResource
    let text: LocalizedStringResource
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.pestoAccent) private var accent

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
        layout {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: 32, alignment: typeSize.isAccessibilitySize ? .leading : .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).pestoQuiet()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
