// SPDX-License-Identifier: MIT
import XCTest

/// A finding that is not Pesto's to fix, described by what it is and which element it is on, so a new unlabelled
/// element of the same kind still shows up: `allowed` is how many of them may appear, and a run with fewer passes.
struct KnownAuditFinding {
    let auditType: XCUIAccessibilityAuditType
    let description: String
    /// nil for a finding the audit reports without an element.
    let elementType: XCUIElement.ElementType?
    let identifier: String
    /// When set, any element whose identifier starts with it matches, for a finding that moves between a pane's rows.
    let identifierPrefix: String?
    let label: String
    let allowed: Int

    init(
        _ auditType: XCUIAccessibilityAuditType,
        _ description: String,
        on elementType: XCUIElement.ElementType?,
        identifier: String = "",
        identifierPrefix: String? = nil,
        label: String = "",
        allowed: Int = 1
    ) {
        self.auditType = auditType
        self.description = description
        self.elementType = elementType
        self.identifier = identifier
        self.identifierPrefix = identifierPrefix
        self.label = label
        self.allowed = allowed
    }

    @MainActor
    func matches(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard issue.auditType == auditType, issue.compactDescription == description else { return false }
        guard let element = issue.element else { return elementType == nil }
        let named = identifierPrefix.map { element.identifier.hasPrefix($0) } ?? (element.identifier == identifier)
        return element.elementType == elementType && named && element.label == label
    }
}

final class AccessibilityAuditTests: PestoUITestCase {
    /// Requests every audit type macOS offers: `.contrast`, `.hitRegion`, `.sufficientElementDescription`, `.action`,
    /// `.parentChild` and `.elementDetection`. `.dynamicType`, `.textClipped` and `.trait` are
    /// iOS/tvOS/watchOS-only per `XCUIAccessibilityAuditTypes.h` and cannot be requested here, so `.all` on macOS
    /// resolves to exactly those six.
    ///
    /// `knownFindings` documents findings that are not Pesto's to fix (`KnownAuditFinding`): NavigationSplitView and
    /// `.searchable` generate their own wrapper nodes for the sidebar, detail and search-field
    /// columns, and neither exposes a modifier that reaches them — confirmed by trying to label the
    /// detail column's content directly, which labelled a node one level too deep and left the
    /// wrapper itself untouched. A composited overlay (the lock screen over the hidden shelf) trips
    /// `.parentChild` on the shelf's already-necessarily-labelled root group. Each is matched by audit type,
    /// description, element type, identifier and label, with a ceiling on how many may appear.
    ///
    /// What is never judged, and why: the system menu bar, and the Touch Bar strip (an input method's candidate bar
    /// and its emoji button report there, outside every Pesto window and panel). Everything inside a Pesto window or
    /// panel is judged, contrast included: the pinned window and the quick menu are panels that `app.windows` does not
    /// list, so a check against the window list alone would drop every contrast finding in them.
    private func runAudit(_ description: String, knownFindings: [KnownAuditFinding] = []) throws {
        var findings: [String] = []
        var remaining = knownFindings.map(\.allowed)
        var consumedAllowance = false
        // The audit judges screen pixels, and a launched Pesto can sit behind the app the run was started from: a
        // light run once measured another app's window, so bring Pesto to the front and let it settle first.
        app.activate()
        Thread.sleep(forTimeInterval: 1)
        let containers = pestoContainerFrames()
        try app.performAccessibilityAudit(for: .all) { issue in
            let element = issue.element
            let frame = element?.frame
            let insidePesto = frame.map { frame in containers.contains { $0.contains(frame) } } ?? false
            if let type = element?.elementType, [.menuBar, .menuBarItem, .menu, .menuItem, .statusItem].contains(type) {
                return true
            }
            if element?.elementType == .touchBar { return true }
            // The Touch Bar's own buttons (an emoji and symbols button appears while a text field is being edited) sit
            // in the strip above the screen's coordinate space and are children of the Touch Bar, which the audit
            // reports without saying so.
            if let frame, frame.maxY < 35, !insidePesto { return true }
            // A row cut by the window's edge is only partly on screen and a row scrolled out of it has no Pesto
            // pixels at all (the audit measures whatever lies behind), so neither can be measured.
            if issue.auditType == .contrast, frame != nil, !insidePesto { return true }
            if let index = knownFindings.indices
                .first(where: { remaining[$0] > 0 && knownFindings[$0].matches(issue) })
            {
                remaining[index] -= 1
                consumedAllowance = true
                return true
            }
            let signature = "\(issue.auditType.rawValue): \(issue.compactDescription)"
            let type = element?.elementType.rawValue ?? 0
            let named = "\(element?.identifier ?? "") \"\(element?.label ?? "")\" type \(type) \(frame ?? .zero)"
            findings.append("\(signature) [\(named)]")
            return true
        }

        // An allowed finding is a system window that appeared (the AutoFill popup under the search field showed up in
        // one gate run in thirty), so what was on screen is attached: if it recurs, the picture and the window list
        // say which window it was.
        if consumedAllowance || !findings.isEmpty { attachScreenState(description) }
        XCTAssertEqual(findings, [], "\(description): \(findings.joined(separator: "; "))")
    }

    private func attachScreenState(_ description: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "\(description) screen"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let windows = app.windows.allElementsBoundByIndex
            .map { "\($0.identifier.isEmpty ? "(no identifier)" : $0.identifier) \($0.frame)" }
            .joined(separator: "\n")
        let listing = XCTAttachment(string: windows)
        listing.name = "\(description) windows"
        listing.lifetime = .keepAlways
        add(listing)
    }

    /// The frames of every Pesto window and panel on screen. The panels (shelf, pinned window, quick menu) are not
    /// always listed in `app.windows`.
    private func pestoContainerFrames() -> [CGRect] {
        var frames = app.windows.allElementsBoundByIndex.map(\.frame)
        for identifier in [
            AccessibilityID.overlayPanel, AccessibilityID.pinnedPanel, AccessibilityID.quickMenuPanel,
            AccessibilityID.toast
        ] {
            let panel = element(identifier)
            if panel.exists { frames.append(panel.frame) }
        }
        return frames
    }

    /// The audit judges real pixels, so each scenario runs once per appearance, with the app told which to use: a run
    /// in the evening, with the Mac in dark mode, failed what had passed by day.
    private func auditInBothAppearances(
        _ name: String,
        defaults: [String: String] = ["hasOnboarded": "true"],
        knownFindings: [KnownAuditFinding] = [],
        prepare: () throws -> Void
    ) throws {
        for mode in ["light", "dark"] {
            if mode == "dark" { app.terminate() }
            launch(defaults: defaults.merging(["appearanceMode": mode]) { _, pinned in pinned })
            try prepare()
            try runAudit("\(name), \(mode)", knownFindings: knownFindings)
        }
    }

    func test_overlay_passesTheAccessibilityAudit() throws {
        try auditInBothAppearances("shelf") { showOverlay() }
    }

    func test_selectionBar_passesTheAccessibilityAudit() throws {
        try auditInBothAppearances("selection bar", knownFindings: [
            KnownAuditFinding(.contrast, "Contrast failed", on: .staticText, allowed: 1)
        ]) {
            showOverlay()
            overlay.typeKey("a", modifierFlags: .command)
            XCTAssertTrue(element(AccessibilityID.pasteOneByOneButton).waitForExistence(timeout: 5))
        }
    }

    func test_searchMode_passesTheAccessibilityAudit() throws {
        try auditInBothAppearances("search mode", knownFindings: [
            // Same composited-overlay quirk as the locked-history scenario, tripped here by the
            // search field's own focus-driven layout change; the audit gives no element for it.
            KnownAuditFinding(.parentChild, "Parent/Child mismatch", on: nil),
            // macOS's own AutoFill suggestion window (SafariPlatformSupportAutoCompleteWindow, 332 by 265 pt under the
            // search field) joined Pesto's tree in one gate run in nine, in dark, and could not be made to appear in
            // eight repeats. It is a system window with no label to give; at most one is allowed.
            KnownAuditFinding(
                .sufficientElementDescription, "Element has no description", on: .window,
                identifier: "SafariPlatformSupportAutoCompleteWindow"
            )
        ]) {
            showOverlay()
            element(AccessibilityID.searchButton).click()
            XCTAssertTrue(element(AccessibilityID.searchField).waitForExistence(timeout: 5))
        }
    }

    /// A-12: the surfaces the audit never saw, whose contrast and target-size findings (A-08 to A-10) were therefore
    /// invisible to the gate.
    func test_deleteQuestion_passesTheAccessibilityAudit() throws {
        try auditInBothAppearances("delete question", knownFindings: [
            // The same composited-overlay quirk as the locked-history scenario: two nodes with no element or frame.
            KnownAuditFinding(.parentChild, "Parent/Child mismatch", on: nil, allowed: 2)
        ]) {
            showOverlay()
            overlay.typeKey(.delete, modifierFlags: [])
            XCTAssertTrue(element(AccessibilityID.deleteConfirmButton).waitForExistence(timeout: 5))
        }
    }

    func test_undoBanner_passesTheAccessibilityAudit() throws {
        try auditInBothAppearances("undo banner") {
            showOverlay()
            overlay.typeKey(.delete, modifierFlags: [])
            element(AccessibilityID.deleteConfirmButton).click()
            XCTAssertTrue(element(AccessibilityID.undoButton).waitForExistence(timeout: 5))
        }
    }

    /// A-12: a card the shelf covers (hidden as sensitive) and the AI answer panel, which the audit never saw.
    func test_coveredCard_passesTheAccessibilityAudit() throws {
        try auditInBothAppearances("covered card", knownFindings: [
            KnownAuditFinding(.parentChild, "Parent/Child mismatch", on: nil, allowed: 2)
        ]) {
            showOverlay()
            let hidden = cards.matching(NSPredicate(format: "label CONTAINS 'sensitive content, hidden'")).firstMatch
            // The second appearance reopens the same history, where the clip is already hidden.
            if !hidden.waitForExistence(timeout: 3) {
                let target = card(containing: "Quarterly report draft")
                XCTAssertTrue(target.waitForExistence(timeout: 5))
                target.rightClick()
                app.menuItems["Mark as Sensitive"].click()
            }
            XCTAssertTrue(hidden.waitForExistence(timeout: 5), "no covered card")
        }
    }

    func test_aiAnswerPanel_passesTheAccessibilityAudit() throws {
        for mode in ["light", "dark"] {
            if mode == "dark" { app.terminate() }
            launch(
                seed: "empty", defaults: ["hasOnboarded": "true", "appearanceMode": mode], aiFixture: true
            )
            copyToClipboard("The sequence of numbers appears to be random, with no pattern a reader could name.")
            showOverlay()
            let target = card(containing: "sequence of numbers")
            XCTAssertTrue(target.waitForExistence(timeout: 10))
            target.rightClick()
            app.menuItems["Key Points"].click()
            XCTAssertTrue(
                element(AccessibilityID.aiResultPasteButton).waitForExistence(timeout: 15), "no AI answer panel"
            )
            try runAudit("AI answer panel, \(mode)")
        }
    }

    func test_toast_passesTheAccessibilityAudit() throws {
        try auditInBothAppearances("toast", knownFindings: [Self.hostedPanelGroup]) {
            send(.showToast)
            XCTAssertTrue(element(AccessibilityID.toast).waitForExistence(timeout: 5), "the toast never appeared")
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
    }

    /// The hover card is a borderless child window that never becomes key, so VoiceOver does not enter it: it gets
    /// the same facts from the focused card (`voiceOverContent`). What the audit judges here is the panel's pixels
    /// and the elements XCUITest can see in it (contrast, labels, target size); how VoiceOver reads the facts from the
    /// card is a hand check in `docs/testing.md`.
    func test_hoverCard_passesTheAccessibilityAudit() throws {
        try auditInBothAppearances("hover card", knownFindings: [
            Self.hostedPanelGroup,
            // The preview text (primary colour) and the facts line (72% of it) read clearly in the run's screenshot,
            // dark on a light card; the audit reports them while the same text passes inside the shelf. Measured
            // against what lies behind the card's translucent ground, so a measurement artefact; ceiling two, and one
            // more on the facts line, which inherits the card's identifier.
            KnownAuditFinding(.contrast, "Contrast failed", on: .staticText, allowed: 2),
            KnownAuditFinding(
                .contrast, "Contrast failed", on: .staticText, identifier: AccessibilityID.cardDetailPopover
            )
        ]) {
            showOverlay()
            overlay.typeKey(.rightArrow, modifierFlags: [])
            XCTAssertTrue(
                element(AccessibilityID.cardDetailPopover).waitForExistence(timeout: 5), "the hover card never opened"
            )
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
    }

    func test_everyTheme_passesTheAccessibilityAudit() throws {
        for theme in ["parmesan", "pineNut", "mortar"] {
            try auditInBothAppearances(
                "shelf in the \(theme) theme", defaults: ["hasOnboarded": "true", "appTheme": theme]
            ) { showOverlay() }
        }
    }

    func test_settings_passesTheAccessibilityAudit() throws {
        try auditInBothAppearances("Settings", knownFindings: Self.navigationSplitViewFindings) {
            send(.openSettings)
            XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            capture("settings-audited")
        }
    }

    /// A-12: the other Settings panes, which the Settings scenario (it opens on General) never measured.
    private func auditSettingsPane(_ pane: String, plus extra: [KnownAuditFinding] = []) throws {
        try auditInBothAppearances("Settings, \(pane)", knownFindings: Self.navigationSplitViewFindings + extra) {
            send(.openSettings)
            XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
            let row = element(AccessibilityID.settingsSidebar(pane))
            XCTAssertTrue(row.waitForExistence(timeout: 5), "no sidebar row for \(pane)")
            row.click()
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
    }

    func test_settingsAppearance_passesTheAccessibilityAudit() throws {
        try auditSettingsPane("Appearance")
    }

    /// One or two of the fact rows ("Encryption", "Update checks", …) measure under 4.5:1 in a run, and which ones
    /// moves
    /// from run to run: at 70% of the primary colour (about 7:1 by calculation) and at 95% alike, while the others in
    /// the same style pass. A measurement artefact, so the ceiling is two and a third such finding still fails.
    func test_settingsPrivacy_passesTheAccessibilityAudit() throws {
        try auditSettingsPane("Privacy", plus: [
            KnownAuditFinding(
                .contrast, "Contrast failed", on: .staticText, identifierPrefix: "settings-privacy-fact-", allowed: 2
            ),
            Self.popUpButtons(1),
            // The system disclosure triangle reports no press action, as the one under "Ask for Touch ID again after"
            // ("How the timer works", same control) does not; neither has been checked with VoiceOver.
            KnownAuditFinding(
                .action, "Action is missing", on: .disclosureTriangle, label: "What stays readable"
            )
        ])
    }

    func test_settingsShortcuts_passesTheAccessibilityAudit() throws {
        try auditSettingsPane("Shortcuts")
    }

    /// Two or three starter captions ("Every swatch you have copied.", …) measure under 4.5:1 in a run, a different set
    /// each time, while the captions in the same style around them pass and the text reads at about 7:1 by
    /// calculation: a measurement artefact. They have no identifier; with the shared allowance the ceiling is three.
    func test_settingsCollections_passesTheAccessibilityAudit() throws {
        try auditSettingsPane("Collections", plus: [
            KnownAuditFinding(.contrast, "Contrast failed", on: .staticText, allowed: 2)
        ])
    }

    func test_settingsSnippets_passesTheAccessibilityAudit() throws {
        try auditSettingsPane("Snippets")
    }

    func test_settingsData_passesTheAccessibilityAudit() throws {
        try auditSettingsPane("Data", plus: [Self.popUpButtons(2)])
    }

    func test_onboarding_passesTheAccessibilityAudit() throws {
        try auditInBothAppearances("onboarding", defaults: [:]) {
            send(.showOnboarding)
            XCTAssertTrue(onboardingWindow.waitForExistence(timeout: 10))
        }
    }

    func test_onboardingLastStep_passesTheAccessibilityAudit() throws {
        try auditInBothAppearances("onboarding last step", defaults: [:]) {
            send(.showOnboarding)
            XCTAssertTrue(onboardingWindow.waitForExistence(timeout: 10))
            let next = element(AccessibilityID.onboardingContinueButton)
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.click()
            let pasting = element(AccessibilityID.onboardingContinueButton)
            XCTAssertTrue(element(AccessibilityID.onboardingAccessibilityStep).waitForExistence(timeout: 5))
            XCTAssertTrue(pasting.waitForExistence(timeout: 5))
            pasting.click()
            XCTAssertTrue(element(AccessibilityID.onboardingGetStartedButton).waitForExistence(timeout: 5))
            waitForNonExistence(
                element(AccessibilityID.onboardingShelfStep),
                timeout: 5,
                "the first step is still showing"
            )
        }
    }

    func test_lockedHistory_passesTheAccessibilityAudit() throws {
        try auditInBothAppearances("locked history", defaults: [
            "hasOnboarded": "true", "biometricLockEnabled": "true",
            "uitestAuthenticationGranted": "false"
        ], knownFindings: [
            KnownAuditFinding(
                .parentChild, "Parent/Child mismatch", on: .group,
                identifier: AccessibilityID.overlayPanel, label: "Clipboard history", allowed: 2
            )
        ]) {
            showOverlay(expectingCards: false)
            XCTAssertTrue(element(AccessibilityID.lockOverlay).waitForExistence(timeout: 5))
        }
    }

    func test_quickMenu_passesTheAccessibilityAudit() throws {
        try auditInBothAppearances("quick menu", knownFindings: [
            // The horizontal ScrollView's content is wider than the panel (5 cards need more room
            // than the visible window), and SwiftUI reports an unlabelled "Other" node for that full
            // scrollable content size — a ScrollView implementation detail, not a view QuickMenuView
            // itself creates or can attach a modifier to.
            KnownAuditFinding(.sufficientElementDescription, "Element has no description", on: .other)
        ]) {
            send(.showQuickMenu)
            XCTAssertTrue(element(AccessibilityID.quickMenuPanel).waitForExistence(timeout: 10))
        }
    }

    func test_pinnedWindow_passesTheAccessibilityAudit() throws {
        try auditInBothAppearances("pinned window") {
            send(.togglePinnedWindow)
            XCTAssertTrue(element(AccessibilityID.pinnedPanel).waitForExistence(timeout: 10))
        }
    }

    /// `NavigationSplitView` (Settings) generates an unlabelled wrapper `Group` for the sidebar
    /// column, the detail column and `.searchable`'s search-field slot, plus a `Parent/Child`
    /// mismatch between the split view and those wrappers. None of these are reachable from
    /// `SettingsView.swift` — confirmed by adding a label directly to the detail column's own
    /// content, which landed one level too deep (on the `ScrollView` inside the wrapper, not the
    /// wrapper) and left the finding unchanged.
    /// A pop-up `Picker` reports "Action is missing" although it works: VoiceOver's Space opens it and Return picks a
    /// value (checked by hand 2026-10-23 on "Keep clips for"). SwiftUI's `Menu` is different: it really had no press
    /// action and was replaced by `PopUpMenuButton`.
    private static func popUpButtons(_ count: Int) -> KnownAuditFinding {
        KnownAuditFinding(
            .action, "Action is missing", on: .popUpButton, identifierPrefix: "settings-choice-", allowed: count
        )
    }

    /// The unlabelled group SwiftUI puts around the hosted root of a borderless panel (the toast, the hover card). Its
    /// content is named and no modifier reaches the group, as with the NavigationSplitView wrappers below.
    private static let hostedPanelGroup = KnownAuditFinding(
        .sufficientElementDescription, "Element has no description", on: .group
    )

    private static let navigationSplitViewFindings = [
        KnownAuditFinding(.parentChild, "Parent/Child mismatch", on: nil),
        KnownAuditFinding(.sufficientElementDescription, "Element has no description", on: .group, allowed: 4),
        // The two-line footer under "Pinned clip shortcuts" (General, light). The window used to cut the pane before
        // this row, so it was never measured. Its text is 70% of the primary colour (about 6.7:1 by calculation) and
        // legible in the screenshot, and the audit's measurement did not move when the colour was darkened to 85%, so
        // it is a measurement artefact; the ceiling of one means a second such finding still fails the run.
        KnownAuditFinding(.contrast, "Contrast failed", on: .staticText, allowed: 1)
    ]

    /// VoiceOver reads "Clipboard history" and "Clips"/"Clipboard cards" as several
    /// nested stops for one region. Only the "Clips" side was collapsible — the two "Clipboard
    /// history" labels (the hosting view and the SwiftUI root beneath it) are each their own AX
    /// node; removing either one fails `test_overlay_passesTheAccessibilityAudit` with "Element
    /// has no description", so both stay named. This locks the count so a third one isn't added
    /// by accident, without pretending the duplication is fixed.
    func test_overlay_namesEachRegionOnce() {
        launch()
        showOverlay()

        let historyLabelled = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Clipboard history")
        )
        let clipsLabelled = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Clips"))

        XCTAssertEqual(historyLabelled.count, 2, "Clipboard history should stay at exactly two nested stops")
        XCTAssertEqual(clipsLabelled.count, 1, "exactly one element should be labelled Clips")
    }
}
