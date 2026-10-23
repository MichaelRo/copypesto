// SPDX-License-Identifier: MIT
// The target app and driver for scripts/bench-latency.sh. It is the app a clip is pasted into (a text view that logs
// the
// moment anything arrives), the one that presses the paste key, and the one that copies clips for the copy bench. It
// reads the clock Pesto's perf timeline uses (CLOCK_UPTIME_RAW), so every number lines up across the two processes.
//
//   BenchTarget paste <work-dir> <runs>
//   BenchTarget copy  <work-dir> <runs>
//
// It saves the general pasteboard before it starts and puts it back when it ends or is interrupted.
import AppKit
import ApplicationServices

func uptimeNanos() -> UInt64 {
    clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
}

// MARK: - Clipboard snapshot

final class ClipboardSnapshot {
    private let url: URL
    private var items: [[String: Data]] = []

    init(url: URL) {
        self.url = url
    }

    func save() {
        items = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var entry: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { entry[type.rawValue] = data }
            }
            return entry
        }
        if let data = try? PropertyListSerialization.data(fromPropertyList: items, format: .binary, options: 0) {
            try? data.write(to: url)
        }
    }

    func restore() {
        let board = NSPasteboard.general
        board.clearContents()
        let restored = items.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }
        if !restored.isEmpty { board.writeObjects(restored) }
    }
}

// MARK: - Fixtures for the copy bench

enum CopyKind: String, CaseIterable {
    case text, richText = "rich text", code, link, colour, file, picture, gif, large

    func write(run: Int, to board: NSPasteboard) {
        // Everything slow is built before the board is touched: setData does not bump the change count, so a poll that
        // lands between clearContents and setData would see an empty board and never see the clip.
        let png = self == .picture ? Self.picture(width: 1600, height: 1000, salt: run) : nil
        let gifBytes = self == .gif ? Self.gif(salt: run) : nil
        let gifStill = self == .gif ? Self.picture(width: 320, height: 320, salt: run) : nil
        let large = self == .large
            ? String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 120_000) + " run \(run)" : nil
        var fileURL: URL?
        if self == .file {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("pesto-bench-copy-\(run).txt")
            try? Data("A file copied in run \(run).\n".utf8).write(to: url)
            fileURL = url
        }
        board.clearContents()
        switch self {
        case .text:
            board.setString(
                "Meet at the north entrance at 14:30, bring the signed forms (run \(run)).",
                forType: .string
            )
        case .richText:
            let text = NSAttributedString(
                string: "Bold and blue words in run \(run).",
                attributes: [.font: NSFont.boldSystemFont(ofSize: 14), .foregroundColor: NSColor.systemBlue]
            )
            if let rtf = try? text.data(
                from: NSRange(location: 0, length: text.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            ) { board.setData(rtf, forType: .rtf) }
            board.setString(text.string, forType: .string)
        case .code:
            let body = (0..<40).map { "func step\($0)(_ value: Int) -> Int { value &+ \($0 + run) }" }
                .joined(separator: "\n")
            board.setString(body, forType: .string)
        case .link:
            let address = "https://developer.apple.com/documentation/swiftdata/\(run)"
            board.setString(address, forType: .string)
            board.setString(address, forType: .URL)
        case .colour:
            board.setString(String(format: "#%06X", 0x1E90FF &+ run * 257), forType: .string)
        case .file:
            if let fileURL { board.writeObjects([fileURL as NSURL]) }
        case .picture:
            if let png { board.setData(png, forType: .png) }
        case .gif:
            if let gifBytes { board.setData(gifBytes, forType: NSPasteboard.PasteboardType("com.compuserve.gif")) }
            if let gifStill { board.setData(gifStill, forType: .png) }
        case .large:
            if let large { board.setString(large, forType: .string) }
        }
    }

    static func picture(width: Int, height: Int, salt: Int) -> Data {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let base = context.data else { return Data() }
        context.setFillColor(NSColor(hue: CGFloat(salt % 50) / 50, saturation: 0.4, brightness: 0.9, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var state = UInt64(salt) &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        for row in (height / 5)..<(height * 4 / 5) {
            for column in (width / 4)..<(width * 3 / 4) {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let offset = row * context.bytesPerRow + column * 4
                pixels[offset] = UInt8(truncatingIfNeeded: state >> 40)
                pixels[offset + 1] = UInt8(truncatingIfNeeded: state >> 48)
                pixels[offset + 2] = UInt8(truncatingIfNeeded: state >> 56)
                pixels[offset + 3] = 255
            }
        }
        guard let image = context.makeImage() else { return Data() }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) ?? Data()
    }

    static func gif(salt: Int) -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "com.compuserve.gif" as CFString, 24, nil) else { return Data() }
        CGImageDestinationSetProperties(
            destination,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        )
        for index in 0..<24 {
            guard let context = CGContext(
                data: nil, width: 320, height: 320, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return Data() }
            context.setFillColor(NSColor(
                hue: CGFloat((index + salt) % 24) / 24,
                saturation: 0.8,
                brightness: 0.9,
                alpha: 1
            ).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 320))
            if let frame = context.makeImage() {
                CGImageDestinationAddImage(
                    destination,
                    frame,
                    [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.05]] as CFDictionary
                )
            }
        }
        CGImageDestinationFinalize(destination)
        return output as Data
    }
}

// MARK: - Driver

/// Tells the system no modifier is held, so a stopped bench cannot leave ⌘ down on the person's keyboard.
func releaseModifiers() {
    for code: CGKeyCode in [54, 55, 56, 58, 59] {
        let event = CGEvent(
            keyboardEventSource: CGEventSource(stateID: .hidSystemState),
            virtualKey: code,
            keyDown: false
        )
        event?.flags = []
        event?.post(tap: .cghidEventTap)
    }
}

@MainActor
final class Bench: NSObject, NSTextViewDelegate {
    let mode: String
    let work: URL
    let runs: Int
    let window = NSWindow(
        contentRect: NSRect(x: 200, y: 300, width: 520, height: 320), styleMask: [.titled], backing: .buffered,
        defer: false
    )
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 320))
    var arrivals: [UInt64] = []
    var rows: [String] = []

    init(mode: String, work: URL, runs: Int) {
        self.mode = mode
        self.work = work
        self.runs = runs
        super.init()
        textView.isRichText = true
        textView.importsGraphics = true
        textView.allowsImageEditing = true
        window.title = "Pesto bench target"
        window.contentView = textView
        NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification, object: textView, queue: .main
        ) { [weak self] _ in
            let now = uptimeNanos()
            MainActor.assumeIsolated { self?.arrivals.append(now) }
        }
    }

    func focus() async {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        for _ in 0..<40
            where NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo
            .processIdentifier
        {
            try? await Task.sleep(for: .milliseconds(50))
        }
        try? await Task.sleep(for: .milliseconds(300))
    }

    func command(_ name: String) {
        let queue = work.appendingPathComponent("commands", isDirectory: true)
        try? FileManager.default.createDirectory(at: queue, withIntermediateDirectories: true)
        let stamp = String(format: "%020llu", DispatchTime.now().uptimeNanoseconds)
        try? Data(name.utf8).write(
            to: queue.appendingPathComponent("\(stamp)-\(UUID().uuidString).cmd"),
            options: .atomic
        )
    }

    func key(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
        let event = CGEvent(
            keyboardEventSource: CGEventSource(stateID: .hidSystemState),
            virtualKey: code,
            keyDown: down
        )
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }

    /// ⌘ and the digit as a person types them: the modifier goes down first and up last, so the system never keeps a
    /// ⌘ it was told about only through a flag on the digit's events.
    func press(digit: Int) {
        let codes: [Int: CGKeyCode] = [1: 18, 2: 19, 3: 20, 4: 21, 5: 23, 6: 22, 7: 26, 8: 28]
        guard let code = codes[digit] else { return }
        key(55, down: true, flags: .maskCommand)
        key(code, down: true, flags: .maskCommand)
        key(code, down: false, flags: .maskCommand)
        key(55, down: false, flags: [])
    }

    func runPaste() async {
        let kinds = ["text", "code", "link", "colour", "file", "picture", "gif", "large"]
        // A paste moves the clip to the front of the shelf, so the card to press is wherever the kind has got to.
        var shelf = kinds
        for kind in kinds {
            for run in 1...runs {
                await focus()
                textView.string = ""
                arrivals.removeAll()
                command("showOverlay")
                try? await Task.sleep(for: .milliseconds(1200))
                let start = uptimeNanos()
                press(digit: (shelf.firstIndex(of: kind) ?? 0) + 1)
                shelf.removeAll { $0 == kind }
                shelf.insert(kind, at: 0)
                var waited = 0
                while arrivals.isEmpty, waited < 60 {
                    try? await Task.sleep(for: .milliseconds(50))
                    waited += 1
                }
                rows.append("\(kind)\t\(run)\t\(start)\t\(arrivals.first ?? 0)")
                try? await Task.sleep(for: .milliseconds(900))
            }
        }
    }

    func runCopy() async {
        await focus()
        command("showOverlay")
        try? await Task.sleep(for: .milliseconds(1500))
        for kind in CopyKind.allCases {
            for run in 1...runs {
                // A copy follows a key or a click; the watcher looks faster just after one, so the bench makes one.
                nudgePointer()
                kind.write(run: run, to: NSPasteboard.general)
                let written = uptimeNanos()
                rows.append("\(kind.rawValue)\t\(run)\t\(written)\t0")
                try? await Task.sleep(for: .milliseconds(kind == .large || kind == .picture ? 2500 : 1500))
            }
        }
    }

    func runOpen() async {
        await focus()
        for run in 1...runs {
            // The usual way the shelf is opened: after a copy made while it was closed.
            nudgePointer()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(
                "Copied before opening the shelf, run \(run) \(UUID().uuidString)",
                forType: .string
            )
            try? await Task.sleep(for: .milliseconds(600))
            let start = uptimeNanos()
            command("showOverlay")
            rows.append("open\t\(run)\t\(start)\t0")
            try? await Task.sleep(for: .milliseconds(2500))
            command("hideOverlay")
            try? await Task.sleep(for: .milliseconds(1200))
        }
    }

    func nudgePointer() {
        let height = NSScreen.main?.frame.height ?? 0
        let here = NSEvent.mouseLocation
        moveMouse(to: CGPoint(x: here.x + 1, y: height - here.y))
    }

    func moveMouse(to point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    /// Rests the pointer on card N of the latency seed, then takes it away. The card lies N - 1 cards (200 wide, 8
    /// apart)
    /// from the shelf's left edge, which has 20 points of padding.
    func runHover() async {
        await focus()
        command("showOverlay")
        try? await Task.sleep(for: .milliseconds(1500))
        guard let screen = NSScreen.main else { return }
        let height = screen.frame.height
        let shelfCenterY = height - screen.visibleFrame.minY - 130
        let cards = [("text", 1), ("code", 2), ("file", 5), ("picture", 6), ("large", 8)]
        for run in 1...runs {
            for (kind, position) in cards {
                let x = screen.visibleFrame.minX + 20 + CGFloat(position - 1) * 208 + 100
                guard x < screen.visibleFrame.maxX - 40 else { continue }
                moveMouse(to: CGPoint(x: x - 60, y: shelfCenterY))
                try? await Task.sleep(for: .milliseconds(120))
                moveMouse(to: CGPoint(x: x, y: shelfCenterY))
                let rested = uptimeNanos()
                rows.append("hover \(kind)\t\(run)\t\(rested)\t0")
                try? await Task.sleep(for: .milliseconds(1800))
                moveMouse(to: CGPoint(x: x, y: height / 3))
                try? await Task.sleep(for: .milliseconds(900))
            }
        }
    }

    /// Long copies for the memory check: `runs` megabyte-sized texts, then a fifth as many screenshot-sized pictures,
    /// with the shelf open. Pesto's footprint is read from outside afterwards.
    func runMemory() async {
        await focus()
        command("showOverlay")
        try? await Task.sleep(for: .milliseconds(1500))
        for run in 1...runs {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(
                String(repeating: "A long copy of text, one megabyte of it. ", count: 25_000) + " \(run)",
                forType: .string
            )
            try? await Task.sleep(for: .milliseconds(450))
        }
        for run in 1...(runs / 4) {
            let picture = CopyKind.picture(width: 2880, height: 1800, salt: run)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(picture, forType: .png)
            try? await Task.sleep(for: .milliseconds(1500))
        }
    }

    func execute() async {
        switch mode {
        case "memory": await runMemory()
        case "paste": await runPaste()
        case "open": await runOpen()
        case "hover": await runHover()
        default: await runCopy()
        }
        try? rows.joined(separator: "\n").appending("\n").write(
            to: work.appendingPathComponent("bench-\(mode).tsv"), atomically: true, encoding: .utf8
        )
    }
}

// MARK: - Entry

let arguments = CommandLine.arguments
guard arguments.count >= 4, let runs = Int(arguments[3]) else {
    FileHandle.standardError.write(Data("usage: BenchTarget paste|copy <work-dir> <runs>\n".utf8))
    exit(2)
}

guard CGPreflightPostEventAccess() || AXIsProcessTrusted() else {
    FileHandle.standardError
        .write(
            Data(
                "BenchTarget: this process cannot post key events; give the app that runs the script Accessibility access\n"
                    .utf8
            )
        )
    exit(3)
}

let work = URL(fileURLWithPath: arguments[2])
let snapshot = ClipboardSnapshot(url: work.appendingPathComponent("clipboard-snapshot.plist"))
snapshot.save()
var signalSources: [DispatchSourceSignal] = []
for signalNumber in [SIGINT, SIGTERM, SIGHUP] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler {
        releaseModifiers()
        snapshot.restore()
        exit(130)
    }
    source.resume()
    signalSources.append(source)
}

let application = NSApplication.shared
application.setActivationPolicy(.regular)
// An app with no Edit menu ignores ⌘V, which would make every keystroke paste look dropped.
let mainMenu = NSMenu()
let appItem = NSMenuItem()
mainMenu.addItem(appItem)
let appMenu = NSMenu()
appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appItem.submenu = appMenu
let editItem = NSMenuItem()
mainMenu.addItem(editItem)
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editItem.submenu = editMenu
application.mainMenu = mainMenu
let bench = MainActor.assumeIsolated { Bench(mode: arguments[1], work: work, runs: runs) }
Task { @MainActor in
    await bench.execute()
    releaseModifiers()
    snapshot.restore()
    exit(0)
}

application.run()
