// SPDX-License-Identifier: MIT
import AppIntents
import PestoCore
import WidgetKit

/// The widget's own settings (ADR 0052): what a tap on a clip does, and whether it shows the newest clips, the pinned
/// ones or one collection (ADR 0060), which it offers from the collections the snapshot carries.
struct RecentClipsConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Recent Clips"
    static let description =
        IntentDescription("Choose which clips the widget shows and what happens when you choose one.")

    @Parameter(title: "When a Clip Is Chosen", default: .copy) var tapAction: WidgetTapChoice

    @Parameter(title: "Show", default: .recent) var source: WidgetSourceChoice

    @Parameter(title: "Collection") var collection: WidgetCollectionEntity?

    static var parameterSummary: some ParameterSummary {
        When(\.$source, .equalTo, WidgetSourceChoice.collection) {
            Summary {
                \.$tapAction
                \.$source
                \.$collection
            }
        } otherwise: {
            Summary {
                \.$tapAction
                \.$source
            }
        }
    }

    init() {}

    init(tapAction: WidgetTapChoice, source: WidgetSourceChoice, collection: WidgetCollectionEntity? = nil) {
        self.tapAction = tapAction
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

enum WidgetTapChoice: String, AppEnum {
    case copy
    case openInPesto
    case openClip

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Action"
    static let caseDisplayRepresentations: [WidgetTapChoice: DisplayRepresentation] = [
        .copy: "Copy",
        .openInPesto: "Open in Pesto",
        .openClip: "Open the Clip"
    ]

    var action: WidgetTapAction {
        switch self {
        case .copy: .copy
        case .openInPesto: .openInPesto
        case .openClip: .openClip
        }
    }
}

enum WidgetSourceChoice: String, AppEnum {
    case recent
    case pinned
    case collection

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Clips"
    static let caseDisplayRepresentations: [WidgetSourceChoice: DisplayRepresentation] = [
        .recent: "Recent",
        .pinned: "Pinned",
        .collection: "Collection"
    ]
}
