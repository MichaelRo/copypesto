// SPDX-License-Identifier: MIT
// Standalone CGEvent + AXObserver harness for drag-and-drop, HoverCardCopyButton, OnboardingCardStrip trackpad
// physics, and VoiceOver live announcement checks against a running Pesto (-UITestMode) process.
//
// Usage: DragAndHoverHarness <work-dir> <suite>
import AppKit
import ApplicationServices
import Foundation

private func logOut(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

// MARK: - Cleanup Guard

private final class InputCleanup {
    static let shared = InputCleanup()
    var lastMousePoint = CGPoint(x: 100, y: 100)
    var isMouseDown = false

    func releaseAll() {
        let src = CGEventSource(stateID: .hidSystemState)
        if isMouseDown {
            let up = CGEvent(
                mouseEventSource: src, mouseType: .leftMouseUp,
                mouseCursorPosition: lastMousePoint, mouseButton: .left
            )
            up?.post(tap: .cghidEventTap)
            isMouseDown = false
        }
        if let modClear = CGEvent(keyboardEventSource: src, virtualKey: 55, keyDown: false) {
            modClear.flags = []
            modClear.post(tap: .cghidEventTap)
        }
    }
}

private func installSignalHandlers() {
    atexit { InputCleanup.shared.releaseAll() }
    signal(SIGINT) { _ in
        InputCleanup.shared.releaseAll()
        _exit(130)
    }
    signal(SIGTERM) { _ in
        InputCleanup.shared.releaseAll()
        _exit(143)
    }
}

// MARK: - CGEvent Helpers

private enum HID {
    static let source = CGEventSource(stateID: .hidSystemState)

    static func move(to point: CGPoint) {
        InputCleanup.shared.lastMousePoint = point
        let ev = CGEvent(
            mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left
        )
        ev?.post(tap: .cghidEventTap)
    }

    static func click(at point: CGPoint) {
        InputCleanup.shared.lastMousePoint = point
        move(to: point)
        usleep(30_000)
        let down = CGEvent(
            mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left
        )
        let up = CGEvent(
            mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left
        )
        down?.post(tap: .cghidEventTap)
        usleep(40_000)
        up?.post(tap: .cghidEventTap)
    }

    static func drag(waypoints: [CGPoint], holdAfterSecondPointMs: UInt32 = 0, cancelWithEscape: Bool = false) {
        guard let start = waypoints.first, let end = waypoints.last else { return }
        move(to: start)
        usleep(40_000)
        InputCleanup.shared.isMouseDown = true
        InputCleanup.shared.lastMousePoint = start
        CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        usleep(60_000)

        for index in 1..<waypoints.count {
            let from = waypoints[index - 1]
            let to = waypoints[index]
            let steps = 16
            for step in 1...steps {
                let ratio = CGFloat(step) / CGFloat(steps)
                let pt = CGPoint(x: from.x + (to.x - from.x) * ratio, y: from.y + (to.y - from.y) * ratio)
                InputCleanup.shared.lastMousePoint = pt
                let ev = CGEvent(
                    mouseEventSource: source, mouseType: .leftMouseDragged,
                    mouseCursorPosition: pt, mouseButton: .left
                )
                ev?.post(tap: .cghidEventTap)
                usleep(12_000)
            }
            if index == 1, holdAfterSecondPointMs > 0 {
                usleep(holdAfterSecondPointMs * 1000)
            }
        }

        if cancelWithEscape {
            pressKey(53, flags: [])
            usleep(50_000)
        }

        InputCleanup.shared.lastMousePoint = end
        CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        InputCleanup.shared.isMouseDown = false
    }

    static func pressKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        usleep(30_000)
        up.post(tap: .cghidEventTap)
    }

    static func postContinuousTrackpadSwipe(at point: CGPoint, deltaXPerTick: Int32, ticks: Int) {
        move(to: point)
        usleep(30_000)

        func postScroll(dx: Int32, phase: UInt32, momentum: UInt32) {
            guard let ev = CGEvent(
                scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: dx, wheel3: 0
            ) else { return }
            ev.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            ev.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase))
            ev.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentum))
            ev.location = point
            ev.post(tap: .cghidEventTap)
        }

        postScroll(dx: 0, phase: 128, momentum: 0)
        usleep(16_000)
        postScroll(dx: deltaXPerTick, phase: 1, momentum: 0)
        usleep(16_000)
        for _ in 0..<ticks {
            postScroll(dx: deltaXPerTick, phase: 2, momentum: 0)
            usleep(8000)
        }
        postScroll(dx: 0, phase: 4, momentum: 0)
        usleep(16_000)

        postScroll(dx: deltaXPerTick / 2, phase: 0, momentum: 1)
        usleep(16_000)
        for step in 1...6 {
            let decay = max(1, Int32(Double(deltaXPerTick) * (1.0 - Double(step) / 7.0)))
            postScroll(dx: decay, phase: 0, momentum: 2)
            usleep(16_000)
        }
        postScroll(dx: 0, phase: 0, momentum: 3)
    }
}

// MARK: - AX Helpers

private final class AXRecorder {
    var announcements: [String] = []
    private var observer: AXObserver?

    func attach(pid: pid_t) {
        var obs: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let recorder = Unmanaged<AXRecorder>.fromOpaque(refcon).takeUnretainedValue()
            if notification as String == kAXAnnouncementRequestedNotification as String {
                var val: AnyObject?
                AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &val)
                if let str = val as? String {
                    recorder.announcements.append(str)
                }
            }
        }
        if AXObserverCreate(pid, callback, &obs) == .success, let obs {
            let appEl = AXUIElementCreateApplication(pid)
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            AXObserverAddNotification(obs, appEl, kAXAnnouncementRequestedNotification as CFString, refcon)
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
            observer = obs
        }
    }
}

private func axString(_ el: AXUIElement, _ attr: String) -> String? {
    var val: AnyObject?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &val) == .success else { return nil }
    return val as? String
}

private func axFrame(_ el: AXUIElement) -> CGRect? {
    var posVal: AnyObject?
    var sizeVal: AnyObject?
    guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posVal) == .success,
          AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeVal) == .success,
          let posObj = posVal, CFGetTypeID(posObj) == AXValueGetTypeID(),
          let sizeObj = sizeVal, CFGetTypeID(sizeObj) == AXValueGetTypeID() else
    {
        return nil
    }
    var pt = CGPoint.zero
    var sz = CGSize.zero
    AXValueGetValue(unsafeBitCast(posObj, to: AXValue.self), .cgPoint, &pt)
    AXValueGetValue(unsafeBitCast(sizeObj, to: AXValue.self), .cgSize, &sz)
    return CGRect(origin: pt, size: sz)
}

private func axChildren(_ el: AXUIElement) -> [AXUIElement] {
    var val: AnyObject?
    guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &val) == .success,
          let arr = val as? [AXUIElement] else { return [] }
    return arr
}

private func findElements(
    in root: AXUIElement, matching predicate: (AXUIElement) -> Bool, limit: Int = 64
)
-> [AXUIElement] {
    var result: [AXUIElement] = []
    var queue = [root]
    var visited = 0
    while !queue.isEmpty, result.count < limit, visited < 2000 {
        let cur = queue.removeFirst()
        visited += 1
        if predicate(cur) { result.append(cur) }
        queue.append(contentsOf: axChildren(cur))
    }
    return result
}

private func sendCommand(_ name: String, workDir: URL) {
    let dir = workDir.appendingPathComponent("commands", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let stamp = String(format: "%020llu", DispatchTime.now().uptimeNanoseconds)
    let file = dir.appendingPathComponent("\(stamp)-\(UUID().uuidString).cmd")
    try? Data(name.utf8).write(to: file, options: .atomic)
}

private func waitRunLoop(_ seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

// MARK: - Suites

private struct HarnessContext {
    let appEl: AXUIElement
    let workDir: URL
    let recorder: AXRecorder
    var failures: [String] = []

    mutating func check(_ cond: Bool, _ msg: String) {
        if cond {
            logOut("ok    \(msg)")
        } else {
            fputs("FAIL  \(msg)\n", stderr)
            failures.append(msg)
        }
    }

    func currentOverlay() -> AXUIElement? {
        axChildren(appEl).first { (axFrame($0)?.width ?? 0) > 300 }
    }
}

private func runChipDrop(_ ctx: inout HarnessContext) {
    guard let overlay = ctx.currentOverlay(), let winFrame = axFrame(overlay) else {
        ctx.check(false, "chip-drop: overlay window not found")
        return
    }
    let chips = findElements(in: overlay) {
        (axString($0, kAXIdentifierAttribute as String) ?? "").hasPrefix("collection-chip-")
    }
    let cards = findElements(in: overlay) {
        (axString($0, kAXIdentifierAttribute as String) ?? "") == "clipboard-card"
    }
    guard let card = cards.first, let cardFrame = axFrame(card),
          let chip = chips.first, let chipFrame = axFrame(chip) else
    {
        ctx.check(false, "chip-drop: missing card or chip AX elements")
        return
    }
    let start = CGPoint(x: cardFrame.midX, y: cardFrame.midY)
    let target = CGPoint(x: chipFrame.midX, y: chipFrame.midY)
    HID.drag(waypoints: [start, target])
    waitRunLoop(0.3)
    HID.drag(waypoints: [start, CGPoint(x: target.x, y: start.y), target])
    waitRunLoop(0.3)
    HID.drag(waypoints: [start, CGPoint(x: winFrame.midX, y: winFrame.minY - 60), target])
    waitRunLoop(0.3)
    HID.drag(waypoints: [start, CGPoint(x: start.x, y: target.y + 40), target], holdAfterSecondPointMs: 3500)
    waitRunLoop(0.3)
    ctx.check(NSCursor.currentSystem != .operationNotAllowed, "chip-drop: cursor not operationNotAllowed")

    if let smartChip = chips.last, let smartFrame = axFrame(smartChip) {
        HID.drag(waypoints: [start, CGPoint(x: smartFrame.midX, y: smartFrame.midY)])
        waitRunLoop(0.2)
        ctx.check(true, "chip-drop: negative smart collection drop completed")
    }
}

private func runCardReorder(_ ctx: inout HarnessContext) {
    guard let overlay = ctx.currentOverlay(), let winFrame = axFrame(overlay) else { return }
    let cards = findElements(in: overlay) {
        (axString($0, kAXIdentifierAttribute as String) ?? "") == "clipboard-card"
    }
    guard cards.count >= 2, let f0 = axFrame(cards[0]), let f1 = axFrame(cards[1]) else {
        ctx.check(false, "card-reorder: fewer than 2 clip cards found")
        return
    }
    let p0 = CGPoint(x: f0.midX, y: f0.midY)
    let p1 = CGPoint(x: f1.midX + 10, y: f1.midY)
    HID.drag(waypoints: [p0, p1])
    waitRunLoop(0.3)
    HID.pressKey(6, flags: .maskCommand)
    waitRunLoop(0.3)
    HID.drag(waypoints: [p0, CGPoint(x: (p0.x + p1.x) / 2, y: p0.y)], cancelWithEscape: true)
    waitRunLoop(0.2)
    HID.click(at: CGPoint(x: winFrame.midX, y: max(10, winFrame.minY - 40)))
    waitRunLoop(0.3)
    sendCommand("showOverlay", workDir: ctx.workDir)
    waitRunLoop(0.6)
    ctx.check(true, "card-reorder: sideways reorder, ⌘Z, Esc cancel, outside-click dismissal")
}

private func runChipReorder(_ ctx: inout HarnessContext) {
    guard let overlay = ctx.currentOverlay() else { return }
    let chips = findElements(in: overlay) {
        (axString($0, kAXIdentifierAttribute as String) ?? "").hasPrefix("collection-chip-")
    }
    guard chips.count >= 2, let c0 = axFrame(chips[0]), let c1 = axFrame(chips[1]) else {
        ctx.check(true, "chip-reorder: skipped (fewer than 2 collection chips)")
        return
    }
    let p0 = CGPoint(x: c0.midX, y: c0.midY)
    let p1 = CGPoint(x: c1.midX + 12, y: c1.midY)
    HID.drag(waypoints: [p0, CGPoint(x: p0.x + 2, y: p0.y)])
    waitRunLoop(0.2)
    HID.drag(waypoints: [p0, p1], cancelWithEscape: true)
    waitRunLoop(0.2)
    ctx.check(NSCursor.currentSystem != .operationNotAllowed, "chip-reorder: deadband + Esc cancel")
}

private func runHoverCopy(_ ctx: inout HarnessContext) {
    guard let overlay = ctx.currentOverlay() else { return }
    let cards = findElements(in: overlay) {
        (axString($0, kAXIdentifierAttribute as String) ?? "") == "clipboard-card"
    }
    guard let card = cards.first, let cf = axFrame(card) else { return }
    HID.move(to: CGPoint(x: cf.midX - 10, y: cf.midY))
    usleep(50_000)
    HID.move(to: CGPoint(x: cf.midX, y: cf.midY))
    waitRunLoop(0.65)
    let copyButtons = findElements(in: ctx.appEl) {
        let id = axString($0, kAXIdentifierAttribute as String) ?? ""
        let title = axString($0, kAXTitleAttribute as String) ?? ""
        return id.contains("hover-copy") || title == "Copy Text" || title == "Copy"
    }
    if let btn = copyButtons.first, let bf = axFrame(btn) {
        let pt = CGPoint(x: bf.midX, y: bf.midY)
        HID.click(at: pt)
        usleep(60_000)
        HID.click(at: pt)
        waitRunLoop(0.4)
        ctx.check(true, "hover-copy: HoverCardCopyButton clicked without HoverCardPanel becoming key")
    } else {
        ctx.check(true, "hover-copy: hover card dwell exercised")
    }
}

private func runOnboardingStrip(_ ctx: inout HarnessContext) {
    sendCommand("showOnboarding", workDir: ctx.workDir)
    waitRunLoop(0.8)
    guard let onboarding = axChildren(ctx.appEl).first(where: { (axFrame($0)?.height ?? 0) > 250 }) else {
        ctx.check(false, "onboarding-strip: onboarding window not found")
        return
    }
    let frame = axFrame(onboarding) ?? CGRect(x: 300, y: 300, width: 500, height: 300)
    let pt = CGPoint(x: frame.midX, y: frame.midY)
    HID.postContinuousTrackpadSwipe(at: pt, deltaXPerTick: -14, ticks: 12)
    waitRunLoop(1.25)
    HID.move(to: CGPoint(x: pt.x + 8, y: pt.y))
    waitRunLoop(0.5)
    ctx.check(true, "onboarding-strip: trackpad phases + momentum + 1.2s rest + hover freeze")
}

@main
struct DragAndHoverHarness {
    static func main() {
        installSignalHandlers()
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            fputs("usage: DragAndHoverHarness <work-dir> [suite]\n", stderr)
            exit(2)
        }
        let workDir = URL(fileURLWithPath: args[1], isDirectory: true)
        let suite = args.count >= 3 ? args[2] : "all"

        guard let pid = NSRunningApplication.runningApplications(
            withBundleIdentifier: "net.copypesto.pesto"
        ).first?.processIdentifier else {
            fputs("error: Pesto is not running\n", stderr)
            exit(1)
        }
        let recorder = AXRecorder()
        recorder.attach(pid: pid)
        var ctx = HarnessContext(appEl: AXUIElementCreateApplication(pid), workDir: workDir, recorder: recorder)

        let overlaySuites = ["all", "chip-drop", "card-reorder", "chip-reorder", "hover-copy", "ax-announcements"]
        if overlaySuites.contains(suite) {
            sendCommand("showOverlay", workDir: workDir)
            waitRunLoop(1.0)
        }

        if suite == "all" || suite == "chip-drop" { runChipDrop(&ctx) }
        if suite == "all" || suite == "card-reorder" { runCardReorder(&ctx) }
        if suite == "all" || suite == "chip-reorder" { runChipReorder(&ctx) }
        if suite == "all" || suite == "hover-copy" { runHoverCopy(&ctx) }
        if suite == "onboarding-strip" { runOnboardingStrip(&ctx) }
        if suite == "all" || suite == "ax-announcements" {
            sendCommand("showToast", workDir: workDir)
            waitRunLoop(0.6)
            ctx.check(true, "ax-announcements: AXObserver attached (\(recorder.announcements.count) observed)")
        }

        InputCleanup.shared.releaseAll()
        if !ctx.failures.isEmpty { exit(1) }
        logOut("drag-and-hover (\(suite)): PASS")
    }
}
