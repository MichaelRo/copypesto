// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

/// The one Edit Text window (ADR 0050): a titled, key window, since the shelf never becomes key. Asking again brings it
/// forward; it takes the new clip only while nothing is typed in it.
@MainActor
final class TextEditWindowController {
    private let appState: AppState
    private let present: (NSWindow) -> Void
    private let didClose: () -> Void
    private(set) var window: NSWindow?
    private(set) var model: TextEditModel?
    private var closeObserver: (any NSObjectProtocol)?

    static let defaultSize = NSSize(width: 520, height: 360)

    init(
        appState: AppState,
        present: @escaping (NSWindow) -> Void = { $0.makeKeyAndOrderFront(nil) },
        didClose: @escaping () -> Void = {}
    ) {
        self.appState = appState
        self.present = present
        self.didClose = didClose
    }

    func open(clipID: UUID, text: String, isMonospaced: Bool) {
        if let window, let model {
            model.load(clipID: clipID, text: text, isMonospaced: isMonospaced)
            present(window)
            return
        }
        let model = TextEditModel(clipID: clipID, text: text, isMonospaced: isMonospaced) { [appState] id, draft in
            await appState.saveEditedText(id: id, text: draft)
        }
        model.onClose = { [weak self] in self?.close() }
        let window = makeWindow(model: model)
        self.model = model
        self.window = window
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.forget() }
        }
        present(window)
    }

    /// Closes the window and drops the draft (Cancel, Save, the History Lock).
    func close() {
        guard let window else { return }
        window.close()
        forget()
    }

    private func forget() {
        guard window != nil else { return }
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        window = nil
        model = nil
        didClose()
    }

    private func makeWindow(model: TextEditModel) -> NSWindow {
        let window = TextEditWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.onEscape = { [weak model] in model?.cancel() }
        // The controller owns this window; the default (true) makes AppKit release it on close as well, and the second
        // release crashes in the next display cycle (NSTouchBarFinder, macOS 27).
        window.isReleasedWhenClosed = false
        window.title = String(localized: "Edit Text")
        window.identifier = NSUserInterfaceItemIdentifier(AccessibilityID.textEditWindow)
        window.contentMinSize = NSSize(width: 360, height: 220)
        let hosting = SafeHostingView(pesto: TextEditView(model: model).environment(appState))
        hosting.setAccessibilityLabel(String(localized: "Edit Text"))
        window.contentView = hosting
        window.setContentSize(Self.defaultSize)
        if let screen = TargetScreen.current() ?? NSScreen.main {
            let frame = screen.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: frame.midX - window.frame.width / 2, y: frame.midY - window.frame.height / 2
            ))
        } else {
            window.center()
        }
        return window
    }
}

private final class TextEditWindow: NSWindow {
    var onEscape: (() -> Void)?

    override func cancelOperation(_: Any?) {
        guard (firstResponder as? any NSTextInputClient)?.hasMarkedText() != true else { return }
        onEscape?()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           event.keyCode == 53,
           event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
           (firstResponder as? any NSTextInputClient)?.hasMarkedText() != true
        {
            onEscape?()
            return
        }
        super.sendEvent(event)
    }
}
