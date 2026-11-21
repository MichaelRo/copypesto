// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// Routes Escape and Down Arrow out of macOS 26's injected Ask Siri search field while a clip context menu is
/// tracking, so typing keeps working while Down Arrow moves focus onto menu items and Escape cancels tracking.
@MainActor
final class ContextMenuKeyBridge {
    private final class TrackedMenu {
        weak var menu: NSMenu?

        init(_ menu: NSMenu) {
            self.menu = menu
        }
    }

    private var trackedMenus: [TrackedMenu] = []
    private nonisolated(unsafe) var monitor: Any?

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    var isMonitoring: Bool {
        monitor != nil
    }

    func beginTracking(menu: NSMenu) {
        trackedMenus.removeAll { $0.menu == nil }
        if !trackedMenus.contains(where: { $0.menu === menu }) {
            trackedMenus.append(TrackedMenu(menu))
        }
        startMonitorIfNeeded()
    }

    func endTracking(menu: NSMenu) {
        trackedMenus.removeAll { $0.menu == nil || $0.menu === menu }
        if trackedMenus.isEmpty {
            stopMonitor()
        }
    }

    func stop() {
        trackedMenus.removeAll()
        stopMonitor()
    }

    nonisolated func handle(_ event: NSEvent) -> NSEvent? {
        nonisolated(unsafe) let unsafeEvent = event
        let shouldConsume = MainActor.assumeIsolated {
            handleOnMain(unsafeEvent)
        }
        return shouldConsume ? nil : event
    }

    private func handleOnMain(_ event: NSEvent) -> Bool {
        trackedMenus.removeAll { $0.menu == nil }
        guard !trackedMenus.isEmpty,
              event.type == .keyDown,
              let window = resolveWindow(for: event),
              Self.isFieldEditorActive(in: window) else
        {
            return false
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers.isEmpty else { return false }

        switch event.keyCode {
        case 53: // Escape
            for entry in trackedMenus.reversed() {
                entry.menu?.cancelTracking()
            }
            return true
        case 125: // Down Arrow
            window.makeFirstResponder(nil)
            return false
        default:
            return false
        }
    }

    private func resolveWindow(for event: NSEvent) -> NSWindow? {
        if let window = event.window { return window }
        if event.windowNumber != 0 {
            if let mapped = NSApp.window(withWindowNumber: event.windowNumber) {
                return mapped
            }
            if let listed = NSApp.windows.first(where: { $0.windowNumber == event.windowNumber }) {
                return listed
            }
        }
        return NSApp.keyWindow
    }

    private static func isFieldEditorActive(in window: NSWindow) -> Bool {
        guard let responder = window.firstResponder else { return false }
        guard responder is NSTextView || responder is NSTextField else { return false }
        if let textInput = responder as? any NSTextInputClient, textInput.hasMarkedText() {
            return false
        }
        return true
    }

    private func startMonitorIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    private func stopMonitor() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}

extension View {
    func bridgeContextMenuKeys(
        _ bridge: ContextMenuKeyBridge,
        isVisible: Bool,
        onBegin: @escaping () -> Void = {}
    )
        -> some View
    {
        onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { note in
            onBegin()
            if isVisible, let menu = note.object as? NSMenu {
                bridge.beginTracking(menu: menu)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { note in
            if let menu = note.object as? NSMenu {
                bridge.endTracking(menu: menu)
            } else {
                bridge.stop()
            }
        }
        .onDisappear { bridge.stop() }
    }
}
