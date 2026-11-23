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
                heightConstraint?.constant = currentHeight
            },
            openURL: { [weak self] url in self?.openHostURL(url) }
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
        registerForTraitChanges([
            UITraitHorizontalSizeClass.self,
            UITraitVerticalSizeClass.self
        ]) { (controller: Self, _) in
            controller.heightConstraint?.constant = controller.currentHeight
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        heightConstraint?.constant = currentHeight
        refresh()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // A keyboard process can stay warm in the background: keep no opened clips in it.
        model.menu = KeyboardMenu(hasFullAccess: false) { nil }
        model.word = nil
        model.dismissedWord = nil
        model.closeSearch()
        openedStamp = nil
    }

    override func selectionDidChange(_ textInput: (any UITextInput)?) {
        super.selectionDidChange(textInput)
        refresh()
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        refresh()
    }

    /// The search page adds a row for the query and three rows of letters, so it is taller than the shelf.
    private var currentHeight: CGFloat {
        KeyboardLayout.totalHeight(
            size: model.menu.keyboardSize,
            isRegular: traitCollection.horizontalSizeClass == .regular,
            isLandscape: traitCollection.verticalSizeClass == .compact,
            isSearching: model.isSearching
        )
    }

    /// Opens the set again only when the app has rewritten it since, so moving between text fields does not decrypt
    /// it each time; the person may switch to Pesto, pin a clip and come back without this process ending.
    private func refresh() {
        model.showsGlobeKey = needsInputModeSwitchKey
        defer {
            // Full Access taken away or the set emptied while searching: the page has nothing left to search.
            if model.isSearching, model.menu.state != .ready {
                model.closeSearch()
                heightConstraint?.constant = currentHeight
            }
        }
        guard hasFullAccess else {
            model.menu = KeyboardMenu(hasFullAccess: false) { nil }
            model.word = nil
            openedStamp = nil
            return
        }
        let file = QuickInsertFile.current
        let stamp = file?.modificationDate
        if openedStamp != .some(stamp) {
            model.menu = KeyboardMenu(hasFullAccess: true) { file.flatMap(Self.open) }
            openedStamp = .some(stamp)
            heightConstraint?.constant = currentHeight
        }
        // Only to search the clips: the last word, while the caret sits at its end; nothing of it is kept (ADR 0062).
        model.word = model.menu.state == .ready
            ? KeyboardWord.before(
                textDocumentProxy.documentContextBeforeInput, after: textDocumentProxy.documentContextAfterInput
            )
            : nil
    }

    private static func open(_ file: QuickInsertFile) -> QuickInsertSet? {
        do {
            return try file.openSet(keys: .shared())
        } catch {
            logger.error("The keyboard's set did not open: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func openHostURL(_ url: URL) {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current is UIApplication,
               current.responds(to: selector),
               let method = class_getInstanceMethod(type(of: current), selector)
            {
                typealias OpenIMP = @convention(c) (
                    AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?
                )
                    -> Void
                let imp = unsafeBitCast(method_getImplementation(method), to: OpenIMP.self)
                imp(current, selector, url as NSURL, [:] as NSDictionary) { [weak self] opened in
                    guard !opened else { return }
                    let target = url.absoluteString
                    Self.logger.warning("UIApplication.open returned false for \(target, privacy: .public)")
                    self?.extensionContext?.open(url, completionHandler: nil)
                }
                return
            }
            responder = current.next
        }
        extensionContext?.open(url, completionHandler: nil)
    }
}
