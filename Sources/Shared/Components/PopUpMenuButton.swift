// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

enum PopUpMenuItem {
    case action(String, () -> Void)
    /// An item with a check mark beside it while `isOn`.
    case choice(String, isOn: Bool, () -> Void)
    case submenu(String, [PopUpMenuItem])
    case header(String)
    case divider
}

/// A button that opens a native menu. SwiftUI's `Menu` exposes no press action on macOS 27, so VoiceOver's Space on
/// it did nothing and the audit reported "Action is missing"; a `Button` has one.
struct PopUpMenuButton<Label: View>: View {
    let items: [PopUpMenuItem]
    /// Changing this opens the menu, so a keyboard action can do what a click does.
    var openRequest = 0
    @ViewBuilder let label: () -> Label
    @State private var anchor = MenuAnchor()

    var body: some View {
        Button(action: present, label: label)
            .background(MenuAnchorView(anchor: anchor))
            .onChange(of: openRequest) { present() }
    }

    private func present() {
        guard let view = anchor.view else { return }
        let targets = MenuActionTargets()
        let menu = nativeMenu(for: items, targets: targets)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.isFlipped ? view.bounds.height : 0), in: view)
    }
}

@MainActor
private func nativeMenu(for items: [PopUpMenuItem], targets: MenuActionTargets) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    for item in items {
        switch item {
        case .divider:
            menu.addItem(.separator())
        case let .header(title):
            menu.addItem(NSMenuItem.sectionHeader(title: title))
        case let .action(title, action):
            menu.addItem(targets.item(title: title, action: action))
        case let .choice(title, isOn, action):
            let entry = targets.item(title: title, action: action)
            entry.state = isOn ? .on : .off
            menu.addItem(entry)
        case let .submenu(title, children):
            let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            entry.submenu = nativeMenu(for: children, targets: targets)
            menu.addItem(entry)
        }
    }
    return menu
}

@MainActor
private final class MenuActionTargets: NSObject {
    private var actions: [() -> Void] = []

    func item(title: String, action: @escaping () -> Void) -> NSMenuItem {
        actions.append(action)
        let item = NSMenuItem(title: title, action: #selector(fire(_:)), keyEquivalent: "")
        item.target = self
        item.tag = actions.count - 1
        return item
    }

    @objc
    private func fire(_ sender: NSMenuItem) {
        actions[sender.tag]()
    }
}
