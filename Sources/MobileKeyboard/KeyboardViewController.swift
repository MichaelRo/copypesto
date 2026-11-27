// SPDX-License-Identifier: MIT
import os
import PestoCore
import SwiftUI
import UIKit

/// Pesto's optional keyboard (ADRs 0061-0063). It types numbers and punctuation into the app, and with Full Access
/// inserts the clips of the sealed quick-insert set that AutoFill reads too; its search page's letters type only into
/// its own field. It never opens the store, the history key or the inbox, never reads the general pasteboard and makes
/// no network request.
final class KeyboardViewController: UIInputViewController {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Keyboard")

    private let model = KeyboardModel()
    private var heightConstraint: NSLayoutConstraint?
    /// The file's modification date when the set was last opened: the outer optional says whether it was opened at
    /// all since the keyboard appeared.
    private var openedStamp: Date??

    override func viewDidLoad() {
        super.viewDidLoad()
        let keys = KeyboardKeys(
            insert: { [weak self] text in self?.textDocumentProxy.insertText(text) },
            deleteBackward: { [weak self] in self?.textDocumentProxy.deleteBackward() },
            switchKeyboard: { [weak self] in self?.advanceToNextInputMode() },
            contextBefore: { [weak self] in self?.textDocumentProxy.documentContextBeforeInput },
            contextAfter: { [weak self] in self?.textDocumentProxy.documentContextAfterInput },
            relayout: { [weak self] in
                guard let self else { return }
                self.updateHeightIfNeeded()
            },
            setKeyboardSize: { [weak self] size in
                guard let self else { return }
                model.keyboardSize = size
                updateHeightIfNeeded()
                guard hasFullAccess else { return }
                do {
                    try KeyboardSizeStore.current?.save(size)
                } catch {
                    Self.logger.error("Saving keyboard size failed: \(error.localizedDescription, privacy: .public)")
                }
            },
            // Opening Pesto needs Full Access on iOS 26 (ADR 0072); without it the keyboard says where the settings
            // are.
            openURL: hasFullAccess ? { [weak self] url in
                guard let self else { return }
                HostURLOpener.open(url, from: self)
            } : nil,
            selectedText: { [weak self] in self?.textDocumentProxy.selectedText }
        )
        followHostAppearance()
        refresh()
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
        registerForTraitChanges([
            UITraitHorizontalSizeClass.self,
            UITraitVerticalSizeClass.self
        ]) { (controller: Self, _) in
            controller.updateHeightIfNeeded()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        followHostAppearance()
        refresh()
        updateHeightIfNeeded()
    }

    private func followHostAppearance() {
        let style = KeyboardAppearanceStyle.style(for: textDocumentProxy.keyboardAppearance)
        if view.overrideUserInterfaceStyle != style { view.overrideUserInterfaceStyle = style }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // A keyboard process can stay warm in the background: keep no opened clips in it.
        model.menu = KeyboardMenu(hasFullAccess: false) { nil }
        model.keyboardSize = .medium
        model.word = nil
        model.dismissedWord = nil
        model.closeSearch()
        model.forgetInsert()
        KeyboardThumbnails.shared.removeAll()
        openedStamp = nil
    }

    override func selectionDidChange(_ textInput: (any UITextInput)?) {
        super.selectionDidChange(textInput)
        refresh()
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        followHostAppearance()
        refresh()
    }

    /// The search page adds a row for the query and three rows of letters, so it is taller than the shelf.
    private var currentHeight: CGFloat {
        KeyboardLayout.totalHeight(
            size: model.keyboardSize,
            isRegular: traitCollection.horizontalSizeClass == .regular,
            isLandscape: traitCollection.verticalSizeClass == .compact,
            isSearching: model.isSearching
        )
    }

    private func updateHeightIfNeeded() {
        let target = currentHeight
        if heightConstraint?.constant != target {
            heightConstraint?.constant = target
        }
    }

    /// Opens the set again only when the app has rewritten it since, so moving between text fields does not decrypt
    /// it each time; the person may switch to Pesto, pin a clip and come back without this process ending.
    private func refresh() {
        let needsSwitch = needsInputModeSwitchKey
        if model.showsGlobeKey != needsSwitch { model.showsGlobeKey = needsSwitch }
        defer {
            // Full Access taken away or the set emptied while searching: the page has nothing left to search.
            if model.isSearching, model.menu.state != .ready {
                model.closeSearch()
                updateHeightIfNeeded()
            }
        }
        guard hasFullAccess else {
            model.menu = KeyboardMenu(hasFullAccess: false) { nil }
            model.keyboardSize = .medium
            model.adopt(query: nil, contextBefore: nil)
            KeyboardThumbnails.shared.removeAll()
            openedStamp = nil
            updateHeightIfNeeded()
            return
        }
        let file = QuickInsertFile.current
        let stamp = file?.modificationDate
        if openedStamp != .some(stamp) {
            // A clip deleted in Pesto must not stay drawable from the old set's pictures.
            KeyboardThumbnails.shared.removeAll()
            model.menu = KeyboardMenu(hasFullAccess: true) { file.flatMap(Self.open) }
            openedStamp = .some(stamp)
            let resolvedSize: KeyboardSize = if let record = KeyboardSizeStore.current?.load(),
                                                model.menu.setCreatedAt.map({ record.updatedAt >= $0 }) ?? true
            {
                record.size
            } else {
                model.menu.keyboardSize
            }
            if model.keyboardSize != resolvedSize {
                model.keyboardSize = resolvedSize
            }
            updateHeightIfNeeded()
        }
        // Selected text (or the last word before the caret) searches the clips; nothing of it is kept (ADR 0062).
        let before = textDocumentProxy.documentContextBeforeInput
        let query = model.menu.state == .ready
            ? KeyboardWord.query(
                selected: textDocumentProxy.selectedText,
                before: before,
                after: textDocumentProxy.documentContextAfterInput
            )
            : nil
        model.adopt(query: query, contextBefore: before)
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
