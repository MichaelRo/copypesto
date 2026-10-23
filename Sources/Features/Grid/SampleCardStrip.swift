// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// Real shelf cards over invented clips, so a picture of the shelf (the welcome screen, the Appearance preview) is the
/// shelf itself and cannot drift from it. The clips live in an in-memory store that nothing else reads; the cards
/// cannot be tapped and fetch nothing. Cards are laid out at their real size and scaled, each wrapped to the scaled
/// size so the row's own width is the width it shows.
struct SampleCardStrip: View {
    enum Kind: CaseIterable {
        case text, link, color, code, note
    }

    @AppStorage(Setting.cardSize) private var cardSizeRaw: String
    @AppStorage(Setting.cardWidth) private var cardWidth: Int
    @State private var samples: Samples?

    let scale: CGFloat
    let focusesFirst: Bool
    /// Marks each card for tests and automation while the cards themselves stay hidden from VoiceOver.
    let cardIdentifier: String?

    init(
        kinds: [Kind], scale: CGFloat, focusesFirst: Bool = false, cardIdentifier: String? = nil
    ) {
        self.scale = scale
        self.focusesFirst = focusesFirst
        self.cardIdentifier = cardIdentifier
        _samples = State(initialValue: Samples.make(kinds: kinds))
    }

    private var size: CGSize {
        CardSize.dimensions(sizeRaw: cardSizeRaw, customWidth: cardWidth)
    }

    var body: some View {
        if let samples {
            HStack(alignment: .top, spacing: 12 * scale) {
                ForEach(Array(samples.items.enumerated()), id: \.element.id) { index, item in
                    card(item, index: index)
                }
            }
            .fixedSize()
            .modelContainer(samples.container)
        }
    }

    private func card(_ item: ClipboardItem, index: Int) -> some View {
        ZStack {
            ClipboardCard(
                item: item,
                isFocused: focusesFirst && index == 0,
                shortcutNumber: index + 1,
                previewsAllowed: false,
                canRevealHidden: false
            )
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale, anchor: .center)
            .accessibilityHidden(true)
            if let cardIdentifier {
                // Almost clear, not clear: a view with nothing to draw is left out of the accessibility tree.
                Color.primary.opacity(0.001)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Self.label(for: item))
                    .accessibilityAddTraits(.isImage)
                    .accessibilityIdentifier(cardIdentifier)
            }
        }
        .frame(width: size.width * scale, height: size.height * scale)
    }

    private static func label(for item: ClipboardItem) -> String {
        switch item.type {
        case .url: "Example link clip"
        case .color: "Example color clip"
        case .code: "Example code clip"
        default: "Example text clip"
        }
    }

    struct Samples {
        let container: ModelContainer
        let items: [ClipboardItem]

        private static func spec(for kind: Kind) -> SampleSpec {
            switch kind {
            case .text:
                SampleSpec(
                    type: .text,
                    text: "Toast the pine nuts 3 min, not 4.",
                    bundleID: "com.apple.Notes",
                    app: "Notes",
                    age: 0
                )
            case .link:
                SampleSpec(
                    type: .url, text: "https://example.com/recipes/pesto-genovese", bundleID: "com.apple.Safari",
                    app: "Safari", age: -120
                )
            case .color:
                SampleSpec(
                    type: .color, text: "#529D6E", bundleID: "com.apple.ColorSyncUtility", app: "ColorSync Utility",
                    age: -180
                )
            case .code:
                SampleSpec(
                    type: .code, text: "let basil = leaves.filter { $0.isFresh }", bundleID: "com.apple.dt.Xcode",
                    app: "Xcode", age: -240, language: "swift"
                )
            case .note:
                SampleSpec(
                    type: .text, text: "Meeting notes, Tuesday: basil order, jar labels, launch date.",
                    bundleID: "com.apple.Notes", app: "Notes", age: -300
                )
            }
        }

        @MainActor
        static func make(kinds: [Kind], now: Date = .now) -> Samples? {
            guard let container = try? ModelContainerSetup.makeInMemory().synced else { return nil }
            let context = container.mainContext
            let items = kinds.enumerated().map { index, kind -> ClipboardItem in
                let spec = spec(for: kind)
                let item = ClipboardItem(
                    timestamp: now.addingTimeInterval(spec.age),
                    type: spec.type,
                    sourceBundleID: spec.bundleID,
                    sourceAppName: spec.app,
                    previewText: spec.text,
                    contentHash: "sample-card-\(index)",
                    byteSize: spec.text.utf8.count,
                    deviceID: "sample-cards",
                    sequenceNumber: Int64(index + 1)
                )
                item.detectedLanguage = spec.language
                return item
            }
            for item in items {
                context.insert(item)
            }
            return Samples(container: container, items: items)
        }
    }
}

private struct SampleSpec {
    let type: ClipboardType
    let text: String
    let bundleID: String
    let app: String
    let age: TimeInterval
    var language: String?
}
