// SPDX-License-Identifier: MIT
import AppKit
import os
import PestoCore
import SwiftUI

// MARK: - NSStatusItem (replaces MenuBarExtra for reliable macOS 26 compatibility)

extension AppDelegate: NSMenuDelegate {
    func setupStatusItem() {
        setupMainMenu()
        // The icon is shown unless the person turned it off in Settings → General.
        if statusItem == nil {
            createStatusItem()
        }
    }

    @MainActor
    func setupMainMenu() {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenuItem())
        mainMenu.addItem(fileMenuItem())
        mainMenu.addItem(editMenuItem())
        let (windowItem, windowMenu) = windowMenuItem()
        mainMenu.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = mainMenu
    }

    @MainActor
    private func appMenuItem() -> NSMenuItem {
        let appMenu = NSMenu(title: "Pesto")
        appMenu.addItem(makeItem("About Pesto", action: #selector(statusShowAbout)))
        appMenu.addItem(.separator())
        appMenu.addItem(makeItem("Settings…", action: #selector(statusOpenSettings), key: ","))
        let servicesItem = NSMenuItem(title: String(localized: "Services"), action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: String(localized: "Services"))
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        if LaunchMode.current.usesSystemIntegrations {
            NSApp.servicesProvider = ServicesProvider.shared
            NSUpdateDynamicServices()
        }
        appMenu.addItem(.separator())
        appMenu.addItem(servicesItem)
        appMenu.addItem(.separator())
        appMenu.addItem(makeItem("Hide Pesto", action: #selector(NSApplication.hide(_:)), key: "h", target: NSApp))
        let hideOthers = makeItem(
            "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), key: "h", target: NSApp
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(makeItem(
            "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), target: NSApp
        ))
        appMenu.addItem(.separator())
        appMenu.addItem(makeItem("Quit Pesto", action: #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
        let item = NSMenuItem()
        item.submenu = appMenu
        return item
    }

    @MainActor
    private func fileMenuItem() -> NSMenuItem {
        let fileMenu = NSMenu(title: String(localized: "File"))
        fileMenu.addItem(
            NSMenuItem(
                title: String(localized: "Close Window"),
                action: #selector(NSWindow.performClose(_:)),
                keyEquivalent: "w"
            )
        )
        let item = NSMenuItem()
        item.submenu = fileMenu
        return item
    }

    @MainActor
    private func editMenuItem() -> NSMenuItem {
        let editMenu = NSMenu(title: String(localized: "Edit"))
        let undoController = EditMenuUndo(appState: appState)
        editMenuUndo = undoController
        editMenu.addItem(undoController.undoItem)
        editMenu.addItem(undoController.redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(
            NSMenuItem(title: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        )
        editMenu.addItem(
            NSMenuItem(title: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        )
        editMenu.addItem(
            NSMenuItem(title: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        )
        editMenu.addItem(
            NSMenuItem(title: String(localized: "Delete"), action: #selector(NSText.delete(_:)), keyEquivalent: "")
        )
        editMenu.addItem(
            NSMenuItem(
                title: String(localized: "Select All"),
                action: #selector(NSText.selectAll(_:)),
                keyEquivalent: "a"
            )
        )
        let item = NSMenuItem()
        item.submenu = editMenu
        return item
    }

    @MainActor
    private func windowMenuItem() -> (NSMenuItem, NSMenu) {
        let windowMenu = NSMenu(title: String(localized: "Window"))
        windowMenu.addItem(NSMenuItem(
            title: String(localized: "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"
        ))
        windowMenu.addItem(NSMenuItem(
            title: String(localized: "Zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""
        ))
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(
            title: String(localized: "Bring All to Front"), action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        ))
        let item = NSMenuItem()
        item.submenu = windowMenu
        return (item, windowMenu)
    }

    /// The icon follows the menu bar. With Light or Dark forced on the app the status window is asked what the bar
    /// looks
    /// like with and without the force; it is pinned (to the bar's own answer) only if forcing reaches it.
    @MainActor
    func applyStatusItemAppearance() {
        guard let button = statusItem?.button, let window = button.window else { return }
        window.appearance = nil
        button.appearance = nil
        guard let forced = NSApp.appearance else { return }
        let underForcedApp = Self.menuBarStyle(of: window)
        NSApp.appearance = nil
        let alone = Self.menuBarStyle(of: window)
        NSApp.appearance = forced
        switch MenuBarAppearance.pin(underForcedApp: underForcedApp, alone: alone) {
        case .dark?: button.appearance = NSAppearance(named: .darkAqua)
        case .light?: button.appearance = NSAppearance(named: .aqua)
        case nil: button.appearance = nil
        }
    }

    private static func menuBarStyle(of window: NSWindow) -> MenuBarAppearance.Style {
        window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    /// The bar's colour changes with the Mac's setting, the wallpaper (so with a Space or a display) and a wake.
    func observeSystemTheme() {
        systemThemeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyStatusItemAppearance() }
        }
        for (center, name) in [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification)
        ] {
            statusAppearanceObservers
                .append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.applyStatusItemAppearance() }
                })
        }
    }

    @MainActor
    private func defaultStatusItemImage() -> NSImage? {
        if let image = NSImage(named: "MenuBarIcon") {
            image.isTemplate = true
            return image
        }
        let fallback = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Pesto")
        fallback?.isTemplate = true
        return fallback
    }

    @MainActor
    private func hiddenStatusItemImage() -> NSImage? {
        statusItemImage(named: "MenuBarIconHidden", fallbackSymbol: "eye.slash", description: "Clip contents hidden")
    }

    @MainActor
    private func lockedStatusItemImage() -> NSImage? {
        statusItemImage(named: "MenuBarIconLocked", fallbackSymbol: "lock.fill", description: "History locked")
    }

    @MainActor
    private func pausedStatusItemImage() -> NSImage? {
        statusItemImage(named: "MenuBarIconPaused", fallbackSymbol: "pause.fill", description: "Capturing paused")
    }

    /// The standing glyph with a badge (`design/source/menubar-glyphs.swift`), or a system symbol if it is missing.
    @MainActor
    private func statusItemImage(named name: String, fallbackSymbol: String, description: String) -> NSImage? {
        let image = NSImage(named: name)
            ?? NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: description)
        image?.isTemplate = true
        return image
    }

    @MainActor
    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = defaultStatusItemImage()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.autosaveName = "net.copypesto.pesto.status"
        statusItem = item
        applyStatusItemAppearance()
        applyStatusItemVisibility()
        trackStatusItemState()
    }

    /// The menu-bar icon can be hidden in Settings → General. Pesto is then reached with the shelf shortcut, and
    /// opening Pesto again from Applications shows Settings (`applicationShouldHandleReopen`).
    func applyStatusItemVisibility() {
        statusItem?.isVisible = AppDefaults.store.value(for: Setting.showMenuBarIcon)
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        if !AppDefaults.store.value(for: Setting.showMenuBarIcon) { openSettingsWindow() }
        return true
    }

    /// The glyph carries a pause badge while capture is paused and says so to VoiceOver, which otherwise learns it only
    /// by opening the
    /// menu. State in the menu bar is instant on purpose: nobody asked for movement there.
    private func trackStatusItemState() {
        applyStatusItemState()
        withObservationTracking {
            _ = appState.isCapturingPaused
            _ = appState.isContentHiddenManually
            _ = appState.isHistoryLocked
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackStatusItemState() }
        }
    }

    private func applyStatusItemState() {
        guard let button = statusItem?.button else { return }
        button.setAccessibilityLabel(String(localized: "Pesto"))
        button.toolTip = String(localized: "Pesto")
        if appState.isHistoryLocked {
            button.image = lockedStatusItemImage()
        } else if appState.isContentHiddenManually {
            button.image = hiddenStatusItemImage()
        } else if appState.isCapturingPaused {
            button.image = pausedStatusItemImage()
        } else {
            button.image = defaultStatusItemImage()
        }
        var states: [String] = []
        if appState.isCapturingPaused { states.append(String(localized: "Capturing paused")) }
        if appState.isHistoryLocked { states.append(String(localized: "History locked")) }
        if appState.isContentHiddenManually { states.append(String(localized: "Clip contents hidden")) }
        button.setAccessibilityValue(states.isEmpty ? nil : states.joined(separator: ", "))
    }

    // MARK: NSMenuDelegate — rebuild on every open so dynamic state is current

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let version = appState.availableUpdateVersion {
            let update = makeItem("Update Available…", action: #selector(statusCheckUpdates))
            update.toolTip = String(localized: "Pesto \(version) is ready to install")
            menu.addItem(update)
            menu.addItem(.separator())
        }

        if appState.activeStack != nil {
            menu.addItem(makeItem("Stop Pasting One by One", action: #selector(statusCancelStack)))
            menu.addItem(.separator())
        }

        if !AccessibilityAccess.isTrusted {
            menu.addItem(makeItem("Grant Accessibility Access…", action: #selector(statusOpenAXSettings)))
            menu.addItem(.separator())
        }

        if LaunchMode.current.usesSystemIntegrations, PasteboardCaptureAccess.current().needsAttention {
            menu.addItem(makeItem(
                "Clipboard Access Limited — Open Settings…",
                action: #selector(statusOpenPasteboardSettings)
            ))
            menu.addItem(.separator())
        }

        menu.addItem(makeItem("Open Shelf", action: #selector(statusShowOverlay), shortcut: .openShelf))
        menu.addItem(makeItem(
            appState.isPinnedWindowVisible ? "Hide Floating Window" : "Show Floating Window",
            action: #selector(statusTogglePinned),
            shortcut: .togglePinnedWindow
        ))
        menu.addItem(.separator())

        menu.addItem(makeItem(
            appState.isCapturingPaused ? "Resume Capturing" : "Pause Capturing",
            action: #selector(statusToggleCapture),
            shortcut: .toggleCapture
        ))
        menu.addItem(makeItem(
            appState.isContentHiddenManually ? "Show Clip Contents" : "Hide Clip Contents",
            action: #selector(statusToggleContentHidden),
            shortcut: .toggleClipContents
        ))
        if AppDefaults.store.value(for: Setting.biometricLockEnabled) {
            if appState.isHistoryLocked {
                menu.addItem(makeItem("Unlock History…", action: #selector(statusShowOverlay)))
            } else {
                menu.addItem(makeItem("Lock History", action: #selector(statusLockHistory)))
            }
        }
        menu.addItem(.separator())

        menu.addItem(makeClearHistoryMenuItem())

        menu.addItem(.separator())
        menu.addItem(makeItem("About Pesto", action: #selector(statusShowAbout)))
        menu.addItem(makeItem("Check for Updates…", action: #selector(statusCheckUpdates)))
        menu.addItem(makeItem("Settings…", action: #selector(statusOpenSettings), key: ","))
        let quit = makeItem("Quit Pesto", action: #selector(NSApplication.terminate(_:)), key: "q", target: NSApp)
        quit.setAccessibilityIdentifier(Self.statusQuitIdentifier)
        menu.addItem(quit)
    }

    private func makeClearHistoryMenuItem() -> NSMenuItem {
        let clearParent = NSMenuItem(title: String(localized: "Clear History"), action: nil, keyEquivalent: "")
        let clearSub = NSMenu(title: "Clear History")
        clearSub.addItem(makeItem("Last 5 Minutes…", action: #selector(statusClearLast5)))
        clearSub.addItem(makeItem("Last Hour…", action: #selector(statusClearLastHour)))
        clearSub.addItem(makeItem("Today…", action: #selector(statusClearToday)))
        clearSub.addItem(.separator())
        clearSub.addItem(makeItem("Everything Except Pinned…", action: #selector(statusClearAll)))
        clearParent.submenu = clearSub
        return clearParent
    }

    static let statusQuitIdentifier = "statusQuit"

    /// An item whose target does not implement its action is disabled by AppKit, so `terminate:` must be aimed at
    /// `NSApp`, not at this delegate.
    private func makeItem(
        _ title: String.LocalizationValue,
        action: Selector,
        key: String = "",
        target: AnyObject? = nil,
        shortcut: GlobalShortcut? = nil
    )
    -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: title), action: action, keyEquivalent: key)
        item.target = target ?? self
        if let binding = shortcut?.binding(in: AppDefaults.store) {
            let name = HotkeyDescription.string(keyCode: UInt32(binding.keyCode), modifiers: 0)
            if name.count == 1 {
                item.keyEquivalent = name.lowercased()
                item.keyEquivalentModifierMask = NSEvent.ModifierFlags(carbon: binding.modifiers)
            }
        }
        return item
    }

    @objc
    func statusOpenPasteboardSettings() {
        PasteboardAccessSettings.open()
    }

    @objc
    func statusOpenAXSettings() {
        AccessibilityPermission.openSystemSettings()
    }

    @objc
    func statusShowAbout() {
        openAboutWindow()
    }

    @objc
    func statusShowOverlay() {
        toggleOverlay(from: .statusMenu)
    }

    @objc
    func statusTogglePinned() {
        togglePinnedWindow()
    }

    @objc
    func statusToggleCapture() {
        Task { await toggleCapture() }
    }

    @objc
    func statusToggleContentHidden() {
        appState.isContentHiddenManually.toggle()
    }

    @objc
    func statusLockHistory() {
        appState.lockHistory()
    }

    @objc
    func statusClearLast5() {
        requestClearHistory(.lastFiveMinutes)
    }

    @objc
    func statusClearLastHour() {
        requestClearHistory(.lastHour)
    }

    @objc
    func statusClearToday() {
        requestClearHistory(.today)
    }

    @objc
    func statusClearAll() {
        requestClearHistory(.all)
    }

    /// The menu bar icon's frame, or nil when Settings has turned the icon off.
    private var statusItemFrame: NSRect? {
        guard statusItem?.isVisible == true else { return nil }
        return statusItem?.button?.window?.frame
    }

    @objc
    func statusCheckUpdates() {
        switch UpdateCheckRoute.choose(isDevelopment: BuildKind.isDevelopment) {
        case .sparkle:
            if appState.availableUpdateVersion != nil || updaterController.updater.sessionInProgress {
                updaterController.checkForUpdates(nil)
            } else {
                appState.updateReminders.beginManualCheck()
                updaterController.updater.checkForUpdatesInBackground()
            }
        case .explainUnavailable:
            toastController.show(.updatesUnavailable, anchor: statusItemFrame)
            ToastAnnouncement.updatesUnavailable()
        }
    }

    func showUpToDateToast() {
        toastController.show(.upToDate, anchor: statusItemFrame)
        ToastAnnouncement.upToDate()
    }

    @objc
    func statusOpenSettings() {
        openSettingsWindow()
    }
}
