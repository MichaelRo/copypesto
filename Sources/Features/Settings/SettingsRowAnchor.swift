// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// What the Settings search asked for: the row to bring into view and the row that is flashing now.
@Observable
@MainActor
final class SettingsRowFocus {
    var target: String?
    private(set) var highlighted: String?
    private var clearing: Task<Void, Never>?

    func request(_ title: String) {
        target = SettingsRowFocus.rowID(title)
    }

    func flash(_ id: String) {
        clearing?.cancel()
        highlighted = id
        clearing = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }
            self?.highlighted = nil
        }
    }

    nonisolated static func rowID(_ title: String) -> String {
        "settings-row-\(title)"
    }
}

private struct SettingsRowAnchor: ViewModifier {
    let title: String
    @Environment(SettingsRowFocus.self) private var focus: SettingsRowFocus?
    @Environment(\.pestoAccent) private var accent

    func body(content: Content) -> some View {
        let id = SettingsRowFocus.rowID(title)
        content
            .id(id)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.opacity(focus?.highlighted == id ? 0.22 : 0))
                    .padding(.horizontal, -6)
                    .padding(.vertical, -3)
            }
            .animation(Motion.animation(.pestoWash), value: focus?.highlighted)
    }
}

private struct SettingsRowScrolling: ViewModifier {
    @Environment(SettingsRowFocus.self) private var focus: SettingsRowFocus?

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .onChange(of: focus?.target, initial: true) { _, id in
                    guard let id, let focus else { return }
                    Task { @MainActor in
                        // The pane has only just been put on screen when a search result opens it.
                        try? await Task.sleep(for: .milliseconds(200))
                        withAnimation(Motion.animation(.pestoMove)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                        focus.flash(id)
                        focus.target = nil
                    }
                }
        }
    }
}

extension View {
    /// Marks a row the Settings search can take the person to: it is scrolled into view and flashes once. `title` is
    /// the search entry's title, and `SettingsIndexDriftTests` fails when an entry has no row.
    func settingsRow(_ title: String) -> some View {
        modifier(SettingsRowAnchor(title: title))
    }

    /// On a pane's form: scrolls to the row the search asked for.
    func settingsRowScrolling() -> some View {
        modifier(SettingsRowScrolling())
    }
}
