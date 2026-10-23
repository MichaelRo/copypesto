// SPDX-License-Identifier: MIT
import AppKit
import Carbon.HIToolbox
import os

/// Registers global hotkeys via the Carbon Event Manager: every `GlobalShortcut` that has a combination (⌘⇧V opens
/// the shelf and ⌃⌥⌘V pastes plain text by default; the rest start unset), and
/// ⌃1–⌃9, which instant-paste the pinned clip assigned to that slot.
@MainActor
public final class HotkeyController {
    public init() {}

    public var onOpenOverlay: (@Sendable () async -> Void)?
    public var onQuickPasteLast: (@Sendable () async -> Void)?
    public var onPastePlainText: (@Sendable () async -> Void)?
    public var onTogglePinnedWindow: (@Sendable () async -> Void)?
    public var onToggleCapture: (@Sendable () async -> Void)?
    public var onToggleClipContents: (@Sendable () async -> Void)?
    /// Called with the 1-based slot index (1–9) when a pinned hotkey fires.
    public var onPinnedHotkey: ((Int) -> Void)?
    /// Slots (1–9) whose ⌃N shortcut is already registered by another process.
    /// Populated during `register()`; presented as disabled in the hotkey picker UI.
    public var unavailableSlots: Set<Int> {
        pinnedSlots.unavailable.union(systemTakenSlots)
    }

    /// Slots whose ⌃N macOS uses itself (Mission Control's Switch to Desktop N when switched on): a hotkey registered
    /// for
    /// one never fires, so it is offered as taken rather than assigned and silent.
    public private(set) var systemTakenSlots: Set<Int> = []

    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "hotkey")
    private var pinnedSlots = PinnedHotkeySlots()
    private var suspension = GlobalHotkeySuspension()

    /// Human-readable names of the main hotkeys that conflict with another app's shortcut.
    /// Populated by `registerConfigurableHotkeys()`. Empty = no conflicts.
    public private(set) var conflictingHotkeys: [String] = []

    private var shortcutRefs: [GlobalShortcut: EventHotKeyRef] = [:]
    private var pinnedHotkeyRefs = [EventHotKeyRef?](repeating: nil, count: 9)
    private var eventHandlerRef: EventHandlerRef?

    private static let signature = OSType(0x5053_544F) // "PSTO"
    /// IDs 3–11 are reserved for Ctrl+1 through Ctrl+9; `GlobalShortcut.carbonID` takes the others.
    private let pinnedBaseID: UInt32 = 3

    /// Virtual key codes for 1–9 on an ANSI keyboard.
    private static let numVKs: [UInt32] = [
        UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3),
        UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5), UInt32(kVK_ANSI_6),
        UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9)
    ]

    public func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        // Install a Carbon event handler. The UnsafeMutableRawPointer bridges `self` so the
        // C callback can dispatch back onto MainActor.
        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let controller = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
                var hotkeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )
                Task { @MainActor in
                    if let shortcut = GlobalShortcut.allCases.first(where: { $0.carbonID == hotkeyID.id }) {
                        HotkeyController.logger.info("Pressed \(shortcut.label, privacy: .public)")
                        await controller.handler(for: shortcut)?()
                    } else if hotkeyID.id >= controller.pinnedBaseID,
                              hotkeyID.id < controller.pinnedBaseID + 9
                    {
                        let slot = Int(hotkeyID.id - controller.pinnedBaseID) + 1
                        controller.onPinnedHotkey?(slot)
                    }
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        registerConfigurableHotkeys()
    }

    /// Claims ⌃N only for slots that currently have a pinned item assigned.
    public func updatePinnedSlots(active: Set<Int>) {
        systemTakenSlots = PinnedHotkeySlots.systemTaken(
            by: SystemShortcuts.enabledBindings(), slotKeyCodes: Self.numVKs.map(Int.init)
        )
        var slots = pinnedSlots
        slots.update(active: active, using: CarbonSlotRegistrar(controller: self))
        pinnedSlots = slots
    }

    fileprivate func registerPinnedSlot(_ slot: Int) -> Bool {
        // Paused: the slot is still wanted, `resume()` claims it.
        guard !suspension.isSuspended else { return true }
        guard !systemTakenSlots.contains(slot) else { return false }
        let index = slot - 1
        let hotkeyID = EventHotKeyID(signature: Self.signature, id: pinnedBaseID + UInt32(index))
        let status = RegisterEventHotKey(
            Self.numVKs[index],
            UInt32(controlKey),
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &pinnedHotkeyRefs[index]
        )
        return status == noErr
    }

    fileprivate func unregisterPinnedSlot(_ slot: Int) {
        if let ref = pinnedHotkeyRefs[slot - 1] { UnregisterEventHotKey(ref) }
        pinnedHotkeyRefs[slot - 1] = nil
    }

    private func handler(for shortcut: GlobalShortcut) -> (@Sendable () async -> Void)? {
        switch shortcut {
        case .openShelf: onOpenOverlay
        case .pastePrevious: onQuickPasteLast
        case .pastePlainText: onPastePlainText
        case .togglePinnedWindow: onTogglePinnedWindow
        case .toggleCapture: onToggleCapture
        case .toggleClipContents: onToggleClipContents
        }
    }

    /// Re-registers only the user-configurable hotkeys (every `GlobalShortcut`).
    /// Call this when UserDefaults values change via `hotkeySettingsChanged` notification.
    public func reregisterMain() {
        unregisterConfigurableHotkeys()
        registerConfigurableHotkeys()
    }

    /// Unregisters every shortcut while a recorder in Settings waits for a combination. A registered Carbon hotkey is
    /// taken before any window sees the key, so without this, recording the combination already in use opened the
    /// shelf instead. Calls nest; `resume()` registers them again once the last recorder is done.
    public func suspend() {
        guard suspension.begin() else { return }
        unregisterConfigurableHotkeys()
        for slot in pinnedSlots.registered {
            unregisterPinnedSlot(slot)
        }
    }

    public func resume() {
        guard suspension.end() else { return }
        registerConfigurableHotkeys()
        for slot in pinnedSlots.registered.sorted() where !registerPinnedSlot(slot) {
            pinnedSlots.markUnavailable(slot)
        }
    }

    private func unregisterConfigurableHotkeys() {
        for ref in shortcutRefs.values {
            UnregisterEventHotKey(ref)
        }
        shortcutRefs = [:]
    }

    private func registerConfigurableHotkeys() {
        guard !suspension.isSuspended else { return }
        // eventHotKeyExistsErr (-9878): the shortcut is owned by another app.
        var conflicts: [String] = []
        for shortcut in GlobalShortcut.allCases {
            guard let binding = shortcut.binding(in: AppDefaults.store) else { continue }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(binding.keyCode), binding.modifiers,
                EventHotKeyID(signature: Self.signature, id: shortcut.carbonID),
                GetApplicationEventTarget(), 0, &ref
            )
            if status == noErr, let ref { shortcutRefs[shortcut] = ref }
            if status == OSStatus(-9878) { conflicts.append(shortcut.label) }
            Self.logger.info("Registered \(shortcut.label, privacy: .public): status \(status, privacy: .public)")
        }
        conflictingHotkeys = conflicts
        // Posted when it is empty too, so a notice about a shortcut that has since been changed goes away.
        NotificationCenter.default.post(
            name: .hotkeyConflictDetected,
            object: nil,
            userInfo: ["conflicts": conflicts]
        )
    }

    public func unregister() {
        unregisterConfigurableHotkeys()
        for ref in pinnedHotkeyRefs {
            if let ref { UnregisterEventHotKey(ref) }
        }
        if let ref = eventHandlerRef { RemoveEventHandler(ref) }
        pinnedHotkeyRefs = [EventHotKeyRef?](repeating: nil, count: 9)
        pinnedSlots = PinnedHotkeySlots()
        eventHandlerRef = nil
    }
    // HotkeyController lives for the app's lifetime; the OS reclaims Carbon event handlers
    // when the process exits. Call unregister() explicitly if early teardown is needed.
}

public extension Notification.Name {
    static let hotkeyConflictDetected = AppIdentity.notificationName("hotkeyConflictDetected")
}

@MainActor
private struct CarbonSlotRegistrar: SlotHotkeyRegistering {
    let controller: HotkeyController

    func register(slot: Int) -> Bool {
        controller.registerPinnedSlot(slot)
    }

    func unregister(slot: Int) {
        controller.unregisterPinnedSlot(slot)
    }
}
