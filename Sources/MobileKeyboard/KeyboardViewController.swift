// SPDX-License-Identifier: MIT
import os
import PestoCore
import SwiftUI
import UIKit

/// Pesto's optional keyboard (ADR 0061). It inserts the starters, and with Full Access the clips of the sealed
/// quick-insert set that AutoFill reads too. It never opens the store, the history key or the inbox, never reads the
/// general pasteboard and has no network.
final class KeyboardViewController: UIInputViewController {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Keyboard")
    private static let compactHeight: CGFloat = 280
    private static let regularHeight: CGFloat = 300

    private let model = KeyboardModel()
    private var heightConstraint: NSLayoutConstraint?
    /// The file's modification date when the set was last opened: the outer optional says whether it was opened at
    /// all since the keyboard appeared.
    private var openedStamp: Date??

    override func viewDidLoad() {
        super.viewDidLoad()
        let keys = KeyboardKeys(
            insert: { [weak self] text in self?.textDocumentProxy.insertText(text) },
            deleteBackward: { [weak self] in self?.textDocumentProxy.deleteBackward() }
        )
        let host = UIHostingController(rootView: KeyboardRootView(model: model, keys: keys, controller: self))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)

        // Without an explicit height the hosted view reports none and the keyboard collapses to nothing.
        let height = view.heightAnchor.constraint(equalToConstant: currentHeight)
        height.priority = .required - 1
        height.isActive = true
        heightConstraint = height
        registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (controller: Self, _) in
            controller.heightConstraint?.constant = controller.currentHeight
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // A keyboard process can stay warm in the background: keep no opened clips in it.
        model.menu = KeyboardMenu(hasFullAccess: false) { nil }
        openedStamp = nil
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        refresh()
    }

    private var currentHeight: CGFloat {
        traitCollection.horizontalSizeClass == .regular ? Self.regularHeight : Self.compactHeight
    }

    /// Opens the set again only when the app has rewritten it since, so moving between text fields does not decrypt
    /// it each time; the person may switch to Pesto, pin a clip and come back without this process ending.
    private func refresh() {
        model.showsGlobeKey = needsInputModeSwitchKey
        guard hasFullAccess else {
            model.menu = KeyboardMenu(hasFullAccess: false) { nil }
            openedStamp = nil
            return
        }
        let file = QuickInsertFile.current
        let stamp = file?.modificationDate
        if let openedStamp, openedStamp == stamp { return }
        model.menu = KeyboardMenu(hasFullAccess: true) { file.flatMap(Self.open) }
        openedStamp = .some(stamp)
    }

    private static func open(_ file: QuickInsertFile) -> QuickInsertSet? {
        do {
            return try file.openSet(keys: .shared())
        } catch {
            logger.error("The keyboard's set did not open: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
