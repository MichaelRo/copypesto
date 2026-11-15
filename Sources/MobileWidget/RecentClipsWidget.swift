// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import WidgetKit

/// Recent Clips on the Home Screen of an iPhone or iPad (ADR 0052): the latest clip, three or six.
struct RecentClipsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppIdentity.widgetKind, provider: RecentClipsProvider()) { entry in
            RecentClipsView(entry: entry)
        }
        .configurationDisplayName("Recent Clips")
        .description("Your newest clips, one touch from the clipboard. Clips with secrets never appear.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
