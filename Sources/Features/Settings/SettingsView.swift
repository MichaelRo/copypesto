// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Top-level Settings window: a sidebar of panes, each a grouped form (ADR 0012).
struct SettingsView: View {
    @Environment(AppState.self) private var appState: AppState
    @Environment(\.shelfActions) private var shelfActions: ShelfActionDispatcher

    @AppStorage(Setting.accentColorHex) private var accentColorHex: String
    @AppStorage(Setting.appTheme) private var appThemeRaw: String
    @AppStorage(Setting.appThemeDark) private var appThemeDarkRaw: String

    @State private var selectedSection: SettingsSection? = SettingsSection(
        rawValue: AppDefaults.store.value(for: Setting.lastSettingsPane)
    ) ?? .general
    @State private var query = ""
    @State private var pickedResult: String?
    @State private var rowFocus = SettingsRowFocus()
    @Environment(\.pestoAccent) private var accent
    @FocusState private var searchFocused: Bool

    private func openRequestedSection() {
        guard let raw = appState.pendingSettingsSection, let section = SettingsSection(rawValue: raw) else { return }
        selectedSection = section
        appState.pendingSettingsSection = nil
        if let row = appState.pendingSettingsRow {
            rowFocus.request(row)
            appState.pendingSettingsRow = nil
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebarList
                .navigationSplitViewColumnWidth(min: 210, ideal: 220, max: 280)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task { await shelfActions.refreshAuthentication() }
                .navigationTitle((selectedSection ?? .general).title)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\((selectedSection ?? .general).title) settings")
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Search settings")
        .searchFocused($searchFocused)
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, idealWidth: 800, minHeight: 640, idealHeight: 720)
        .pestoAccented(stored: accentColorHex, theme: appThemeRaw, darkTheme: appThemeDarkRaw)
        .environment(rowFocus)
        .onAppear {
            openRequestedSection()
            searchFocused = false
        }
        .task {
            // macOS hands the sidebar search field the keyboard focus after the window is up, which drew its ring in
            // the first picture of every session; a moment later it is let go again.
            try? await Task.sleep(for: .milliseconds(300))
            if query.isEmpty { searchFocused = false }
        }
        .onChange(of: selectedSection) { _, section in
            if let section { AppDefaults.store.set(section.rawValue, for: Setting.lastSettingsPane) }
            if query.isEmpty { searchFocused = false }
        }
        .onChange(of: appState.pendingSettingsSection) { _, _ in openRequestedSection() }
    }

    // MARK: - Sidebar

    private func moveSection(by step: Int) -> KeyPress.Result {
        let all = SettingsSection.allCases
        guard let current = selectedSection.flatMap(all.firstIndex(of:)) else { return .ignored }
        let next = current + step
        guard all.indices.contains(next) else { return .handled }
        selectedSection = all[next]
        return .handled
    }

    @ViewBuilder
    private var sidebarList: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            // A list, so VoiceOver reads it as one, with the selection drawn here: the system sidebar paints its
            // selection in the system accent and ignores `.tint`, and the pill keeps the text on a solid ground.
            List(SettingsSection.allCases) { section in
                SettingsSidebarRow(section: section, isSelected: selectedSection == section) {
                    selectedSection = section
                }
                .listRowBackground(
                    selectedSection == section
                        ? RoundedRectangle(cornerRadius: 7, style: .continuous).fill(accent.opacity(0.18))
                        : nil
                )
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
            .onKeyPress(.upArrow) { moveSection(by: -1) }
            .onKeyPress(.downArrow) { moveSection(by: 1) }
            .accessibilityLabel("Settings sections")
            .toolbar(removing: .sidebarToggle)
        } else {
            searchResults
                .toolbar(removing: .sidebarToggle)
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        let results = SettingsIndex.search(query)
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List(results, id: \.title, selection: $pickedResult) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                    Text(entry.pane).pestoCaption()
                }
                .tag(entry.title)
                .accessibilityIdentifier(AccessibilityID.settingsSearchResult(entry.title))
            }
            .onChange(of: pickedResult) { _, title in
                guard let title, let entry = SettingsIndex.entries.first(where: { $0.title == title }) else { return }
                selectedSection = SettingsSection(rawValue: entry.pane)
                rowFocus.request(entry.title)
                pickedResult = nil
                query = ""
            }
            .listStyle(.sidebar)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection ?? .general {
        case .general:
            GeneralPane()
                .environment(appState)
        case .appearance:
            AppearanceSettings()
        case .privacy:
            PrivacyPane()
                .environment(appState)
        case .shortcuts:
            ShortcutsPane()
                .environment(appState)
        case .collections:
            CollectionsSettings()
                .environment(appState)
        case .snippets:
            SnippetsSettings()
                .environment(appState)
        case .data:
            DataPane(hasStorage: appState.historyContainer != nil)
                .environment(appState)
        }
    }
}

private struct SettingsSidebarRow: View {
    @Environment(\.pestoAccent) private var accent
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                Text(section.title)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(AccessibilityID.settingsSidebar(section.rawValue))
    }
}

// MARK: - Section enum

enum SettingsSection: String, CaseIterable, Hashable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case privacy = "Privacy"
    case shortcuts = "Shortcuts"
    case collections = "Collections"
    case snippets = "Snippets"
    case data = "Data"

    var id: Self {
        self
    }

    var title: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .general: "gear"
        case .appearance: "paintbrush"
        case .privacy: "hand.raised"
        case .shortcuts: "keyboard"
        case .collections: "tray.2"
        case .snippets: "curlybraces"
        case .data: "externaldrive"
        }
    }
}
