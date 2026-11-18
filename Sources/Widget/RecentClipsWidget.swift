// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import WidgetKit

/// Recent Clips on the Home Screen of an iPhone or iPad (ADR 0052) and on the Mac's desktop (ADR 0058): the latest
/// clip, three or six, as Pesto cards.
struct RecentClipsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: AppIdentity.widgetKind, intent: RecentClipsConfiguration.self, provider: RecentClipsProvider()
        ) { entry in
            RecentClipsView(entry: entry)
        }
        .configurationDisplayName("Recent Clips")
        .description("Your newest clips as Pesto cards, ready to copy. Clips with secrets never appear.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
