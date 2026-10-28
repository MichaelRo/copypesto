// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftData
import SwiftUI

extension AppDelegate {
    /// Website screenshots only: a window behind everything of ours, covering the area between the menu bar and the
    /// Dock, so the shelf's glass shows the palette instead of the desktop. UI-test mode only; never shown to a user.
    func showMarketingBackdropIfRequested() {
        let configuration = RuntimeConfiguration.current
        guard configuration.mode == .uiTest, configuration.backdrop != .none,
              let screen = NSScreen.main else { return }
        let window = NSWindow(
            contentRect: screen.visibleFrame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        // Above every other app's windows (they sit at .normal) so no desktop shows through the glass, and below the
        // shelf and its popovers (.floating).
        window.level = NSWindow.Level(rawValue: 1)
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.identifier = NSUserInterfaceItemIdentifier("marketing-backdrop")
        window.setAccessibilityLabel(String(localized: "Backdrop"))
        window.contentView = SafeHostingView(pesto: MarketingBackdropView(style: configuration.backdrop))
        window.orderFront(nil)
        MarketingBackdropHolder.window = window
        // The Settings window is an ordinary window, so it would be hidden behind the backdrop.
        NotificationCenter.default
            .addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
                guard let key = note.object as? NSWindow else { return }
                MainActor.assumeIsolated {
                    guard key.identifier?.rawValue == AccessibilityID.settingsWindow else { return }
                    key.level = NSWindow.Level(rawValue: 2)
                }
            }
    }

    /// The marketing seed's two collections and its snippet, imported pinned like the first-run samples, with the
    /// snippet given the first pinned-clip shortcut so the screenshots show it.
    func seedMarketingCollections() async {
        guard let container = appState.historyContainer else { return }
        _ = try? await PasteMigrator(modelContainer: container).migrate(records: MarketingSeed.collectionRecords())
        let context = ModelContext(container)
        for board in (try? context.fetch(FetchDescriptor<Pinboard>())) ?? [] {
            guard let style = MarketingSeed.collectionStyles[board.name] else { continue }
            board.symbolName = style.symbol
            board.colorHex = style.colorHex
        }
        let title = "Thank you"
        let pinned = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.isPinned })
        if let snippet = try? context.fetch(pinned).first(where: { $0.customTitle == title }) {
            snippet.pinnedHotkeyIndex = 1
        }
        // The restyle is saved whether or not the snippet was found: it used to ride on the snippet's save, and a
        // missing snippet left every collection on the generic tray.
        try? context.saveOrRollback()
    }

    /// The Lunch Rush profile: the three snippets pinned with their ⌃ shortcuts, the supplier links gathered by a
    /// smart collection, and the pesto picture marked sensitive.
    func seedLunchRush() async {
        guard let container = appState.historyContainer else { return }
        let then = Date.now.addingTimeInterval(-3600)
        let records = LunchRushSeed.snippets.enumerated().map { index, snippet in
            PasteImportRecord(
                pinboard: nil, title: snippet.title, timestamp: then.addingTimeInterval(Double(-index) * 60),
                sourceBundleID: "com.apple.Notes",
                representations: [.init(
                    uti: "public.utf8-plain-text",
                    dataBase64: Data(snippet.text.utf8).base64EncodedString()
                )]
            )
        }
        _ = try? await PasteMigrator(modelContainer: container).migrate(records: records)
        let context = ModelContext(container)
        let items = (try? context.fetch(FetchDescriptor<ClipboardItem>())) ?? []
        for snippet in LunchRushSeed.snippets {
            guard let item = items.first(where: { $0.customTitle == snippet.title }) else { continue }
            item.isPinned = true
            item.pinnedHotkeyIndex = snippet.shortcut
        }
        let pictures = items.filter { $0.type == .image }.sorted { $0.timestamp > $1.timestamp }
        pictures.first?.isNSFW = true
        let rule = PredicateRule(field: .contentShape, op: .equals, value: .string("link"))
        let ruleSet = PredicateRuleSet(combinator: .and, groups: [.init(combinator: .and, rules: [rule])])
        if let data = try? SmartCollectionPredicate.encodeRuleSet(ruleSet) {
            context.insert(Pinboard(
                name: LunchRushSeed.supplierCollection, symbolName: "link", colorHex: "#5B8DEF", sortOrder: 0,
                isSmart: true, smartPredicateData: data
            ))
        }
        try? context.saveOrRollback()
    }
}

/// Keeps the backdrop window alive; the delegate is at its size limit, so the property cannot live there.
@MainActor
enum MarketingBackdropHolder {
    static var window: NSWindow?
}
