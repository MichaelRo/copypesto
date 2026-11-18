// SPDX-License-Identifier: MIT
import AppIntents

struct PestoMobileShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddToPestoIntent(),
            phrases: ["Add to \(.applicationName)", "Save to \(.applicationName)"],
            shortTitle: "Add to Pesto",
            systemImageName: "text.badge.plus"
        )
        AppShortcut(
            intent: AddClipboardToPestoIntent(),
            phrases: ["Add my clipboard to \(.applicationName)", "Add clipboard to \(.applicationName)"],
            shortTitle: "Add Clipboard to Pesto",
            systemImageName: "doc.on.clipboard"
        )
        AppShortcut(
            intent: SearchPestoIntent(),
            phrases: ["Search \(.applicationName)"],
            shortTitle: "Search Pesto",
            systemImageName: "magnifyingglass"
        )
    }
}
