// SPDX-License-Identifier: MIT
import AppIntents
import PestoCore
import WidgetKit

/// Per-widget settings for Lock Screen accessory widgets (ADR 0065). Opt-in defaults to `false` so no clip text
/// appears on a locked phone until the person explicitly allows it on that widget.
struct LockScreenClipsConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Lock Screen Clips"
    static let description = IntentDescription(
        "Choose whether clips can appear on the Lock Screen and which source to show. Secrets never appear."
    )

    @Parameter(
        title: "Show Clips on Lock Screen",
        description: "Shows clip text on a locked device. Secrets are never shown.",
        default: false
    ) var showsClipsOnLockScreen: Bool

    @Parameter(title: "Show", default: .recent) var source: WidgetSourceChoice

    @Parameter(title: "Collection") var collection: WidgetCollectionEntity?

    static var parameterSummary: some ParameterSummary {
        When(\.$source, .equalTo, WidgetSourceChoice.collection) {
            Summary {
                \.$showsClipsOnLockScreen
                \.$source
                \.$collection
            }
        } otherwise: {
            Summary {
                \.$showsClipsOnLockScreen
                \.$source
            }
        }
    }

    init() {}

    init(
        showsClipsOnLockScreen: Bool = false,
        source: WidgetSourceChoice = .recent,
        collection: WidgetCollectionEntity? = nil
    ) {
        self.showsClipsOnLockScreen = showsClipsOnLockScreen
        self.source = source
        self.collection = collection
    }

    var clipSource: WidgetClipSource {
        switch source {
        case .recent: .recent
        case .pinned: .pinned
        case .collection: .collection(collection?.id)
        }
    }
}
