// SPDX-License-Identifier: MIT
import AppKit
import os
import SwiftUI
import Testing
@testable import Pesto

private final class ReentrantConstraintProbe {
    var wroteDuringLayout = false
    var valueChangedDuringLayout: Bool?
    weak var targetHosting: SafeHostingView?
}

private struct ReentrantProbeRepresentable: NSViewRepresentable {
    let probe: ReentrantConstraintProbe
    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_: NSView, context _: Context) {}
    func sizeThatFits(_ proposal: ProposedViewSize, nsView _: NSView, context _: Context) -> CGSize? {
        if let targetHosting = probe.targetHosting {
            let before = targetHosting.needsUpdateConstraints
            targetHosting.needsUpdateConstraints = !before
            probe.valueChangedDuringLayout = (targetHosting.needsUpdateConstraints != before)
            probe.wroteDuringLayout = true
        }
        return CGSize(width: proposal.width ?? 100, height: proposal.height ?? 40)
    }
}

extension HostedGlobals {
    @Suite("A button in the hover card panel", .serialized)
    @MainActor
    final class HoverCardClickTests {
        private func sendClick(to window: NSWindow, at point: NSPoint) throws {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
                ))
                NSApp.sendEvent(event)
            }
        }

        @Test("a first click lands through NSApp.sendEvent while OverlayPanel is key, without stealing key focus")
        func whenClickedViaAppEventWhileOverlayIsKey_thenButtonFiresWithoutStealingFocus() async throws {
            let overlay = OverlayPanel()
            overlay.setFrame(NSRect(x: 100, y: 100, width: 400, height: 180), display: false)
            NSApp.activate(ignoringOtherApps: true)
            overlay.makeKeyAndOrderFront(nil)
            defer { overlay.orderOut(nil) }

            let panel = HoverCardPanel()
            #expect(!panel.canBecomeKey)
            #expect(panel.hosting.allowsFirstMouse)
            #expect(!SafeHostingView(pesto: EmptyView()).allowsFirstMouse)

            var copies = 0
            panel.hosting.setPestoRoot(
                HoverCardCopyButton(quiet: .gray, copy: {
                    copies += 1
                    return true
                })
                .padding(16)
                .fixedSize()
            )
            panel.ignoresMouseEvents = false
            overlay.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
            defer {
                overlay.removeChildWindow(panel)
                panel.orderOut(nil)
            }

            try await Task.sleep(for: .milliseconds(300))
            let size = NSSize(width: 200, height: 70)
            panel.setFrame(NSRect(x: 120, y: 290, width: size.width, height: size.height), display: true)
            panel.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))

            let resignedCount = OSAllocatedUnfairLock(initialState: 0)
            let observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: overlay, queue: .main
            ) { _ in
                resignedCount.withLock { $0 += 1 }
            }
            defer { NotificationCenter.default.removeObserver(observer) }

            let wasOverlayKey = overlay.isKeyWindow
            try sendClick(to: panel, at: NSPoint(x: size.width / 2, y: size.height / 2))
            try await Task.sleep(for: .milliseconds(200))

            #expect(copies == 1)
            #expect(!panel.isKeyWindow)
            #expect(overlay.isKeyWindow == wasOverlayKey)
            #expect(resignedCount.withLock { $0 } == 0)

            let outside = NSWindow(
                contentRect: NSRect(x: 500, y: 500, width: 120, height: 120),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            outside.isReleasedWhenClosed = false
            outside.makeKeyAndOrderFront(nil)
            defer { outside.orderOut(nil) }
            try await Task.sleep(for: .milliseconds(50))

            if wasOverlayKey {
                #expect(resignedCount.withLock { $0 } >= 1)
            }
        }

        @Test("SafeHostingView drops re-entrant needsUpdateConstraints writes during layout")
        func whenLayoutWritesNeedsUpdateConstraints_thenReentrantWriteIsDropped() {
            let probe = ReentrantConstraintProbe()
            let hosting = SafeHostingView(pesto: ReentrantProbeRepresentable(probe: probe))
            hosting.frame = NSRect(x: 0, y: 0, width: 100, height: 40)
            hosting.layout()

            probe.targetHosting = hosting
            hosting.needsUpdateConstraints = true
            #expect(hosting.needsUpdateConstraints)

            hosting.frame = NSRect(x: 0, y: 0, width: 120, height: 40)
            hosting.needsUpdateConstraints = false
            hosting.needsLayout = true
            hosting.layout()

            #expect(probe.wroteDuringLayout)
            #expect(probe.valueChangedDuringLayout == false)
        }
    }
}
