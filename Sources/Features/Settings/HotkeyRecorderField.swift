// SPDX-License-Identifier: MIT
import AppKit
import Carbon.HIToolbox
import PestoCore
import SwiftUI

/// A clickable badge that, when activated, captures the next key+modifier combo typed by the user. Pesto's own global
/// shortcuts are paused while it listens, so the combination already in use can be recorded again; Esc cancels, and a
/// combination another shortcut has, or the system keeps, is refused with the reason. A shortcut that starts unset
/// shows a dashed "Record Shortcut" slot until one is recorded. One trailing menu holds Change, Reset to Default and
/// Turn Off.
struct HotkeyRecorderField: View {
    let shortcut: GlobalShortcut

    @AppStorage private var storedKeyCode: Int
    @AppStorage private var storedModifiers: Int
    @Environment(AppState.self) private var appState: AppState
    @Environment(\.pestoAccent) private var accent
    @State private var isRecording = false
    @State private var eventMonitor: Any?
    @State private var resignObserver: Any?
    @State private var refusal: String?
    @State private var takenByAnotherApp = false

    init(shortcut: GlobalShortcut) {
        self.shortcut = shortcut
        _storedKeyCode = AppStorage(shortcut.keyCodeSetting)
        _storedModifiers = AppStorage(shortcut.modifiersSetting)
    }

    private var binding: HotkeyBinding? {
        shortcut.binding(storedKeyCode: storedKeyCode, storedModifiers: storedModifiers)
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Button {
                    isRecording ? stopRecording() : startRecording()
                } label: {
                    if isRecording {
                        Label("Press the new keys…", systemImage: "record.circle")
                            .foregroundStyle(accent)
                            .frame(minWidth: 100)
                    } else if let binding {
                        keycaps(for: binding)
                    } else {
                        Text("Record Shortcut")
                            .foregroundStyle(accent)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 24)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(accent.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            )
                    }
                }
                .buttonStyle(.plain)
                .help(binding == nil ? "" : String(localized: "Click to record a different shortcut"))
                .accessibilityLabel(Text(verbatim: shortcut.label))
                .accessibilityValue(accessibilityValue)
                .accessibilityIdentifier(AccessibilityID.shortcutRecorder(shortcut.carbonID))

                optionsMenu
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: shortcut.label)
                if let refusal {
                    Text(refusal).pestoCaption()
                } else if takenByAnotherApp, binding != nil {
                    Text("Another app already uses this, so it will not work. Record a different shortcut.")
                        .pestoCaption()
                        .foregroundStyle(Color.statusBad)
                }
            }
        }
        .onAppear { takenByAnotherApp = appState.hotkeyController.conflictingHotkeys.contains(shortcut.label) }
        .onReceive(NotificationCenter.default.publisher(for: .hotkeyConflictDetected)) { note in
            let conflicts = note.userInfo?["conflicts"] as? [String] ?? []
            takenByAnotherApp = conflicts.contains(shortcut.label)
        }
        .onDisappear { stopRecording() }
    }

    private var optionsMenu: some View {
        var items: [PopUpMenuItem] = [.action(String(localized: "Change…"), startRecording)]
        if let defaultBinding = shortcut.defaultBinding, binding != defaultBinding {
            items.append(.action(String(localized: "Reset to Default"), reset))
        }
        if binding != nil { items.append(.action(String(localized: "Turn Off"), turnOff)) }
        return PopUpMenuButton(items: items) {
            Image(systemName: "ellipsis.circle")
                .frame(minWidth: 24, minHeight: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Options for \(shortcut.label)"))
        .accessibilityIdentifier(AccessibilityID.shortcutMenu(shortcut.carbonID))
    }

    private var accessibilityValue: String {
        if isRecording { return String(localized: "Recording. Press the new keys.") }
        guard let binding else { return String(localized: "Not set") }
        return HotkeyDescription.string(keyCode: UInt32(binding.keyCode), modifiers: binding.modifiers)
    }

    private func keycaps(for binding: HotkeyBinding) -> some View {
        let keyName = HotkeyDescription.string(keyCode: UInt32(binding.keyCode), modifiers: 0)
        let full = HotkeyDescription.string(keyCode: UInt32(binding.keyCode), modifiers: binding.modifiers)
        let symbols = full.dropLast(keyName.count).map(String.init) + [keyName]
        return HStack(spacing: 4) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Keycap(symbol: symbol)
            }
        }
        .accessibilityHidden(true)
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        refusal = nil
        Announcer.announce(String(localized: "Recording. Press the new keys. Escape cancels."))
        appState.hotkeyController.suspend()
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
        ) { [self] _ in
            MainActor.assumeIsolated { stopRecording() }
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if event.keyCode == UInt16(kVK_Escape), mods.isEmpty {
                stopRecording()
                return nil
            }
            guard !mods.isEmpty else { return event }
            let newKeyCode = Int(event.keyCode)
            let newMods = mods.carbonModifiers
            let others = shortcut.others(in: AppDefaults.store)
            let system = SystemShortcuts.enabledBindings()
            switch HotkeyRecording.evaluate(keyCode: newKeyCode, modifiers: newMods, others: others, system: system) {
            case .accepted:
                // Written before the shortcuts come back, so they come back with the new one.
                storedKeyCode = newKeyCode
                storedModifiers = Int(newMods)
                NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)
                let spoken = HotkeyDescription.spoken(keyCode: UInt32(newKeyCode), modifiers: newMods)
                Announcer.announce(String(localized: "\(shortcut.label) is now \(spoken)."))
            case .needsModifier:
                refusal = String(localized: "Hold ⌘, ⌥ or ⌃ with the key.")
            case .reservedBySystem:
                refusal = String(localized: "Every app uses that one. Add another modifier.")
            case let .clash(name):
                refusal = String(localized: "That is already the shortcut for \u{201C}\(name)\u{201D}. Pick another.")
            case .takenBySystem:
                refusal = String(
                    localized: "macOS already uses that. Pick another, or change it in System Settings → Keyboard."
                )
            }
            if let refusal { Announcer.announce(refusal, priority: .high) }
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let observer = resignObserver {
            NotificationCenter.default.removeObserver(observer)
            resignObserver = nil
        }
        guard isRecording else { return }
        isRecording = false
        appState.hotkeyController.resume()
    }

    /// Off for good: no shortcut is registered until one is recorded or Reset brings the default back.
    private func turnOff() {
        refusal = nil
        storedKeyCode = 0
        storedModifiers = shortcut.isOptional ? 0 : GlobalShortcut.disabledMarker
        NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)
    }

    private func reset() {
        refusal = nil
        storedKeyCode = shortcut.defaultBinding?.keyCode ?? 0
        storedModifiers = Int(shortcut.defaultBinding?.modifiers ?? 0)
        NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)
    }
}
