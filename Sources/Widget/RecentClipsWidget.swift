// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import WidgetKit

/// Recent Clips on the Home Screen of an iPhone or iPad (ADR 0052) and on the Mac's desktop (ADR 0059): one card, two,
/// four or (on iPad) eight, with page buttons on medium and large (ADR 0067).
struct RecentClipsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: AppIdentity.widgetKind, intent: RecentClipsConfiguration.self, provider: RecentClipsProvider()
        ) { entry in
            RecentClipsView(entry: entry)
        }
        .configurationDisplayName("Recent Clips")
        .description(
            "Your newest clips, pinned clips or a collection as Pesto cards. Clips with secrets never appear."
        )
        .supportedFamilies(Self.families)
    }

    #if os(iOS)
    static let families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
    #else
    static let families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
    #endif
}
