// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The app in front, then the three others copied from most this week; any of them can be switched on to show only
/// that app's clips.
struct AppChipsRow: View {
    @Environment(AppState.self) private var appState: AppState
    @AppStorage(Setting.pinnedAppChipBundleIDs) private var pinnedAppChipsRaw: String
    @AppStorage(Setting.additionalExcludedBundleIDs) private var additionalExcludedIDsRaw: String
    let recent: [SourceApp]
    let frontmost: SourceApp?
    var allApps: [SourceApp] = []
    /// When the user has custom collections on the bar, app chips show only their icon at rest so the collections have
    /// room; when there are no collections, app chips show their names at rest too.
    var collapsesLabels = true

    @State private var intent = ChipHoverIntent()
    @State private var measuredWidths: [String: CGFloat] = [:]
    @State private var pointerX: CGFloat?

    static let spacing: CGFloat = 8
    private static let restWidth: CGFloat = 24

    /// The row, in order. The command bar publishes the same list to `AppState.appChips` for ⌥⌘[ and ⌥⌘].
    static func chips(
        recent: [SourceApp], frontmost: SourceApp?, allApps: [SourceApp] = [], pinnedBundleIDs: [String] = []
    )
    -> [SourceApp] {
        AppChips.chips(
            frontmost: frontmost,
            recent: recent,
            ownBundleID: Bundle.main.bundleIdentifier,
            pinnedBundleIDs: pinnedBundleIDs,
            knownApps: allApps,
            resolveAppName: installedAppName
        )
    }

    private var chips: [SourceApp] {
        Self.chips(
            recent: recent,
            frontmost: frontmost,
            allApps: allApps,
            pinnedBundleIDs: AppChips.pinnedIDs(from: pinnedAppChipsRaw)
        )
    }

    private static func installedAppName(for bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
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
        .accessibilityElement(children: .contain)
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
        .contentShape(Rectangle())
        .onPreferenceChange(ChipWidthKey.self) { measuredWidths = $0 }
        .onChange(of: appState.isOverlayVisible) { resetPointer() }
        .onDisappear { resetPointer() }
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
        let isPinned = AppChips.pinnedIDs(from: pinnedAppChipsRaw).contains(app.bundleID)
        return PestoChip(
            label: app.name, icon: "app.badge.checkmark",
            iconImage: SourceIconCache.shared.image(forBundleID: app.bundleID), isActive: isActive,
            collapsesLabel: collapsesLabels,
            isRevealed: intent.expanded == index,
            helpText: isActive
                ? String(localized: "Showing clips from \(app.name), click to remove")
                : String(localized: "Show clips from \(app.name)")
        ) {
            toggleFilter(for: app.bundleID)
        }
        .contextMenu {
            Button {
                toggleFilter(for: app.bundleID)
            } label: {
                Label(
                    isActive ? "Clear \(app.name) Filter" : "Show Only \(app.name)",
                    systemImage: isActive
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
            }
            Button {
                pinnedAppChipsRaw = AppChips.togglePinned(app.bundleID, in: pinnedAppChipsRaw)
            } label: {
                Label(isPinned ? "Unpin App" : "Pin App", systemImage: isPinned ? "pin.slash" : "pin")
            }
            if !ExclusionRules.defaultExcludedBundleIDs.contains(app.bundleID) {
                Divider()
                Button(role: .destructive) {
                    ignoreCopies(from: app.bundleID)
                } label: {
                    Label("Ignore Copies from \(app.name)", systemImage: "eye.slash")
                }
            }
        }
        .accessibilityIdentifier(AccessibilityID.appChip(app.bundleID))
        .background(GeometryReader { proxy in
            Color.clear.preference(key: ChipWidthKey.self, value: [app.bundleID: proxy.size.width])
        })
    }

    private func toggleFilter(for bundleID: String) {
        if appState.appChipFilter.contains(bundleID) {
            appState.appChipFilter.remove(bundleID)
        } else {
            appState.appChipFilter.insert(bundleID)
        }
    }

    private func ignoreCopies(from bundleID: String) {
        var additions = ExclusionRules.userAdditions(from: additionalExcludedIDsRaw).sorted()
        if !additions.contains(bundleID) {
            additions.append(bundleID)
            additionalExcludedIDsRaw = additions.sorted().joined(separator: ", ")
        }
        pinnedAppChipsRaw = AppChips.removePinned(bundleID, in: pinnedAppChipsRaw)
        appState.appChipFilter.remove(bundleID)
    }

    /// Where each chip sits when none is open: the pointer is matched to these, so a chip growing under it never
    /// changes which chip it is on.
    private func slot(at x: CGFloat) -> Int? {
        guard collapsesLabels else { return nil }
        let restWidths = chips.map { app in
            appState.appChipFilter.contains(app.bundleID) ? measuredWidths[app.bundleID] ?? Self.restWidth : Self
                .restWidth
        }
        let expanded = intent.expanded.flatMap { open -> ChipSlots.Expanded? in
            guard chips.indices.contains(open), let width = measuredWidths[chips[open].bundleID] else { return nil }
            return ChipSlots.Expanded(index: open, width: width)
        }
        return ChipSlots.target(x: x, restWidths: restWidths, spacing: Self.spacing, expanded: expanded)
    }

    /// The shelf closing or the row leaving the screen can swallow the pointer's exit; nothing may stay open from it.
    private func resetPointer() {
        intent = ChipHoverIntent()
        pointerX = nil
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
