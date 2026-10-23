// SPDX-License-Identifier: MIT
import AppKit
import Darwin
import SQLite3
import XCTest

/// Base class for UI tests. Every test launches Pesto with `-UITestMode`: a private working directory,
/// seeded history, a private pasteboard and stubbed Accessibility and paste, so a run never touches the
/// user's real clipboard, store or preferences.
@MainActor
class PestoUITestCase: XCTestCase {
    var app = XCUIApplication()
    private(set) var session = ""
    private(set) var workDirectory = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        session = "ui-\(UUID().uuidString.prefix(8))"
        workDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pesto-uitest-\(session)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        app.terminate()
        NSPasteboard(name: NSPasteboard.Name("io.pesto.uitest.\(session)")).clearContents()
        try? FileManager.default.removeItem(at: workDirectory)
        try await super.tearDown()
    }

    // MARK: - Launch

    func launch(
        seed: String = "basic",
        accessibility: String = "trusted",
        defaults: [String: String] = ["hasOnboarded": "true"],
        backdrop: String? = nil,
        motion: Bool = false,
        realDevice: Bool = false,
        importFixture: String? = nil,
        keyLoss: Bool = false,
        aiFixture: Bool = false,
        recordsPerfTimeline: Bool = false,
        timeout: TimeInterval = 90
    ) {
        app = XCUIApplication()
        // Motion is off in a UI-test launch so no spring or fade makes a wait or a picture depend on frame timing; a
        // test about something that moves (an animated picture) asks for it.
        app.launchArguments = motion ? ["-UITestMode", "-UITestMotion"] : ["-UITestMode"]
        var environment = [
            "PESTO_UITEST_SESSION": session,
            "PESTO_UITEST_DIR": workDirectory.path,
            "PESTO_UITEST_SEED": seed,
            "PESTO_UITEST_ACCESSIBILITY": accessibility
        ]
        for (key, value) in defaults {
            environment["PESTO_UITEST_DEFAULT_\(key)"] = value
        }
        if let backdrop { environment["PESTO_UITEST_BACKDROP"] = backdrop }
        if realDevice { environment["PESTO_UITEST_REAL_DEVICE"] = "1" }
        if let importFixture { environment["PESTO_UITEST_IMPORT_FIXTURE"] = importFixture }
        if keyLoss { environment["PESTO_UITEST_KEYLOSS"] = "1" }
        if aiFixture { environment["PESTO_UITEST_AI_FIXTURE"] = "1" }
        if recordsPerfTimeline { environment["PESTO_UITEST_PERF_TIMELINE"] = "1" }
        app.launchEnvironment = environment
        app.launch()
        // The lost-key alert (`keyLoss`) is modal, and the ready marker comes when it is answered.
        if !keyLoss { waitUntilReady(timeout: timeout) }
    }

    func relaunch() {
        app.terminate()
        try? FileManager.default.removeItem(at: workDirectory.appendingPathComponent(UITestSupport.readyFileName))
        app.launch()
        waitUntilReady(timeout: 90)
    }

    func waitUntilReady(timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if UITestSupport.readyMarker(in: workDirectory) != nil { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("App did not finish seeding within \(timeout) s")
    }

    // MARK: - Driving the app

    func send(_ command: UITestCommand) {
        do {
            try UITestCommandQueue.enqueue(command, in: workDirectory)
        } catch {
            XCTFail("could not enqueue \(command): \(error)")
        }
    }

    /// Simulates a copy in another app by writing to the private pasteboard Pesto is watching.
    func copyToClipboard(_ text: String) {
        let board = NSPasteboard(name: NSPasteboard.Name("io.pesto.uitest.\(session)"))
        board.clearContents()
        board.setString(text, forType: .string)
    }

    var overlay: XCUIElement {
        app.descendants(matching: .any).matching(identifier: AccessibilityID.overlayPanel).firstMatch
    }

    var cards: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: AccessibilityID.card)
    }

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func cardCount(containing text: String) -> Int {
        cards.matching(NSPredicate(format: "label CONTAINS %@", text)).count
    }

    func card(containing text: String) -> XCUIElement {
        cards.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Moves the pointer off the overlay strip so a hover popover from the previous step is not open.
    func parkPointer() {
        let above = overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(
            dx: 0,
            dy: -250
        ))
        above.hover()
    }

    func showOverlay(expectingCards: Bool = true) {
        send(.showOverlay)
        if !overlay.waitForExistence(timeout: 10) {
            dumpState("overlay-missing")
            XCTFail("overlay did not appear")
        }
        if expectingCards, !cards.firstMatch.waitForExistence(timeout: 10) {
            dumpState("no-cards")
            XCTFail("no cards rendered")
        }
        if overlay.exists { parkPointer() }
    }

    var settingsWindow: XCUIElement {
        app.windows.matching(identifier: AccessibilityID.settingsWindow).firstMatch
    }

    var onboardingWindow: XCUIElement {
        app.windows.matching(identifier: AccessibilityID.onboardingWindow).firstMatch
    }

    /// Writes the accessibility tree and a screenshot next to the other captures, for diagnosing a failure.
    func dumpState(_ step: String) {
        capture(step)
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = "\(step)-tree"
        attachment.lifetime = .keepAlways
        add(attachment)
        let commandLog = (try? String(
            contentsOf: workDirectory.appendingPathComponent("commands.log"),
            encoding: .utf8
        ))
            ?? "(no commands received)"
        let logAttachment = XCTAttachment(string: commandLog)
        logAttachment.name = "\(step)-commands"
        logAttachment.lifetime = .keepAlways
        add(logAttachment)
        let testName = name.replacingOccurrences(of: "[^A-Za-z0-9_]", with: "", options: .regularExpression)
        try? app.debugDescription.write(
            to: captureDirectory.appendingPathComponent("\(testName)-\(step).txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval = 5, _ message: String = "") {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, message)
    }

    // MARK: - Store

    /// How many clipboard items the app left in its store, read straight from the SQLite file. Only
    /// meaningful once the app has quit.
    func storedItemCount() -> Int? {
        var db: OpaquePointer?
        let path = workDirectory.appendingPathComponent("clips.store").path
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM ZCLIPBOARDITEM", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int(statement, 0))
    }

    /// Quits through the status menu and returns once the process is gone.
    func quitFromStatusMenu(timeout: TimeInterval = 40) {
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10), "no menu-bar item")
        guard let pid = UITestSupport.readyMarker(in: workDirectory)?.processID else {
            XCTFail("no process id in the ready marker")
            return
        }
        statusItem.click()
        let quit = app.menuItems.matching(identifier: "statusQuit").firstMatch
        XCTAssertTrue(quit.waitForExistence(timeout: 5))
        quit.click()
        let deadline = Date().addingTimeInterval(timeout)
        while kill(pid, 0) == 0, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    /// Seconds the app spent between `applicationShouldTerminate` and `applicationWillTerminate`, from its own
    /// timestamped log. The click itself is not timed: XCUITest waits for the app to idle before it delivers
    /// one, which can take ~13 s.
    func terminationDelay() -> TimeInterval? {
        let log = (try? String(contentsOf: workDirectory.appendingPathComponent("commands.log"), encoding: .utf8)) ?? ""
        func stamp(_ event: String) -> Double? {
            log.split(separator: "\n").first { $0.hasPrefix("\(event) ") }
                .flatMap { Double($0.dropFirst(event.count + 1)) }
        }
        guard let asked = stamp("shouldTerminate"), let terminating = stamp("willTerminate") else { return nil }
        return terminating - asked
    }

    // MARK: - Paste log

    /// What the stubbed paste would have delivered, oldest first.
    func pastedTexts() -> [String] {
        let url = workDirectory.appendingPathComponent("paste-log.jsonl")
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return content.split(separator: "\n").compactMap { line in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                return nil
            }
            return object["text"] as? String
        }
    }

    func waitForPaste(count: Int, timeout: TimeInterval = 8) -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, pastedTexts().count < count {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return pastedTexts()
    }

    // MARK: - Screenshots

    /// Saves a PNG of the app's own window (never the full screen, which would include whatever else is open on
    /// the developer's desktop) to `PESTO_SCREENSHOT_DIR`, and attaches it to the test result.
    func capture(_ step: String, of element: XCUIElement? = nil) {
        guard let target = element ?? (overlay.exists ? overlay : visibleWindow), target.exists else { return }
        if element != nil || !overlay.exists { bringAppToFront() }
        let screenshot = target.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = step
        attachment.lifetime = .keepAlways
        add(attachment)

        let testName = name.replacingOccurrences(of: "[^A-Za-z0-9_]", with: "", options: .regularExpression)
        try? screenshot.pngRepresentation.write(to: captureDirectory.appendingPathComponent("\(testName)-\(step).png"))
    }

    /// A screenshot of an element is the screen's pixels under it, so a window of another app in front of an ordinary
    /// window ends up in the picture: the About picture showed an open chat for weeks. The floating shelf needs none
    /// of this, it is above every app.
    private func bringAppToFront() {
        app.activate()
        let deadline = Date().addingTimeInterval(5)
        while app.state != .runningForeground, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(app.state, .runningForeground, "the app is not in front: a picture would show whatever is")
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }

    /// The whole screen, for what spans windows (the hover card above the shelf).
    func captureScreen(_ step: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = step
        attachment.lifetime = .keepAlways
        add(attachment)
        let testName = name.replacingOccurrences(of: "[^A-Za-z0-9_]", with: "", options: .regularExpression)
        try? screenshot.pngRepresentation.write(to: captureDirectory.appendingPathComponent("\(testName)-\(step).png"))
    }

    private var visibleWindow: XCUIElement? {
        app.windows.allElementsBoundByIndex.first { $0.exists && $0.frame.width > 0 }
    }

    private var captureDirectory: URL {
        let base = ProcessInfo.processInfo.environment["PESTO_SCREENSHOT_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? workDirectory.appendingPathComponent("screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}
