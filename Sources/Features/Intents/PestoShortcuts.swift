// SPDX-License-Identifier: MIT
import AppIntents

struct PestoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenShelfIntent(),
            phrases: ["Open \(.applicationName)", "Show my clipboard in \(.applicationName)"],
            shortTitle: "Open Pesto",
            systemImageName: "list.clipboard"
        )
        AppShortcut(
            intent: SearchPestoIntent(),
            phrases: ["Search \(.applicationName)", "Search my clipboard in \(.applicationName)"],
            shortTitle: "Search Pesto",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: PasteFromPestoIntent(),
            phrases: ["Paste from \(.applicationName)"],
            shortTitle: "Copy from Pesto",
            systemImageName: "doc.on.clipboard"
        )
        AppShortcut(
            intent: SetClipContentsHiddenIntent(),
            phrases: ["Hide clip contents in \(.applicationName)"],
            shortTitle: "Hide Clip Contents",
            systemImageName: "eye.slash"
        )
        AppShortcut(
            intent: CopyToPestoIntent(),
            phrases: ["Copy text to \(.applicationName)"],
            shortTitle: "Copy Text to Pesto",
            systemImageName: "text.badge.plus"
        )
    }
}
