// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The app in front, then the three others copied from most this week; any of them can be switched on to show only
/// that app's clips.
struct AppChipsRow: View {
    @Environment(AppState.self) private var appState: AppState
    let recent: [SourceApp]
    let frontmost: SourceApp?
    /// When the user has custom collections on the bar, app chips show only their icon at rest so the collections have
    /// room; when there are no collections, app chips show their names at rest too.
    var collapsesLabels = true

    @State private var intent = ChipHoverIntent()
    @State private var activeWidths: [String: CGFloat] = [:]
    @State private var openedWidth: CGFloat = 80
    @State private var pointerX: CGFloat?

    static let spacing: CGFloat = 8
    private static let restWidth: CGFloat = 24

    private var chips: [SourceApp] {
        AppChips.chips(frontmost: frontmost, recent: recent, ownBundleID: Bundle.main.bundleIdentifier)
    }

    var body: some View {
        if !chips.isEmpty {
            row
        }
    }

    private var row: some View {
        HStack(spacing: Self.spacing) {
            ForEach(Array(chips.enumerated()), id: \.element.bundleID) { index, app in
                chip(app, index: index)
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case let .active(point):
                pointerX = point.x
                intent.pointerMoved(over: slot(at: point.x), at: Self.now)
            case .ended:
                pointerX = nil
                intent.pointerMoved(over: nil, at: Self.now)
            }
        }
        .onPreferenceChange(ChipWidthKey.self) { widths in
            activeWidths = widths.filter { appState.appChipFilter.contains($0.key) }
            if let open = intent.expanded, chips.indices.contains(open), let width = widths[chips[open].bundleID] {
                openedWidth = width
            }
        }
        .onChange(of: chips.map(\.bundleID)) {
            // The apps behind the chips changed under a resting pointer: start over, and decide again where it is.
            intent = ChipHoverIntent()
            if let pointerX { intent.pointerMoved(over: slot(at: pointerX), at: Self.now) }
        }
        .task(id: intent.isPending) {
            while !Task.isCancelled, intent.isPending {
                try? await Task.sleep(for: .milliseconds(30))
                withAnimation(Motion.animation(.pestoQuick)) { intent.tick(at: Self.now) }
            }
        }
    }

    private func chip(_ app: SourceApp, index: Int) -> some View {
        let isActive = appState.appChipFilter.contains(app.bundleID)
        return PestoChip(
            label: app.name, icon: "app.badge.checkmark",
            iconImage: SourceIconCache.shared.image(forBundleID: app.bundleID), isActive: isActive,
            collapsesLabel: collapsesLabels,
            isRevealed: intent.expanded == index,
            helpText: isActive
                ? String(localized: "Showing clips from \(app.name), click to remove")
                : String(localized: "Show clips from \(app.name)")
        ) {
            if isActive {
                appState.appChipFilter.remove(app.bundleID)
            } else {
                appState.appChipFilter.insert(app.bundleID)
            }
        }
        .accessibilityIdentifier(AccessibilityID.appChip(app.bundleID))
        .background(GeometryReader { proxy in
            Color.clear.preference(key: ChipWidthKey.self, value: [app.bundleID: proxy.size.width])
        })
    }

    /// Where each chip sits when none is open: the pointer is matched to these, so a chip growing under it never
    /// changes which chip it is on.
    private func slot(at x: CGFloat) -> Int? {
        guard collapsesLabels else { return nil }
        let restWidths = chips.map { activeWidths[$0.bundleID] ?? Self.restWidth }
        let expanded = intent.expanded.map { ChipSlots.Expanded(index: $0, width: openedWidth) }
        return ChipSlots.target(x: x, restWidths: restWidths, spacing: Self.spacing, expanded: expanded)
    }

    private static var now: Double {
        ProcessInfo.processInfo.systemUptime
    }
}

private struct ChipWidthKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}
