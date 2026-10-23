// SPDX-License-Identifier: MIT
import Carbon.HIToolbox
import Foundation
import Testing
@testable import PestoCore

@Suite("Global shortcuts")
struct GlobalShortcutTests {
    private let command = cmdKey
    private let shift = shiftKey
    private let option = optionKey
    private let control = controlKey

    @Test("nothing stored means the shortcut's own default, and the four optional ones have none")
    func whenNothingStored_thenDefaultOrUnset() {
        #expect(GlobalShortcut.openShelf.binding(storedKeyCode: 0, storedModifiers: 0)
            == HotkeyBinding(keyCode: kVK_ANSI_V, modifiers: UInt32(command | shift)))
        #expect(GlobalShortcut.pastePlainText.binding(storedKeyCode: 0, storedModifiers: 0)
            == HotkeyBinding(keyCode: kVK_ANSI_V, modifiers: UInt32(control | option | command)))
        for optional in [GlobalShortcut.pastePrevious, .togglePinnedWindow, .toggleCapture, .toggleClipContents] {
            #expect(optional.binding(storedKeyCode: 0, storedModifiers: 0) == nil)
        }
    }

    @Test("a key code of zero is the A key once a modifier is stored, not a request for the default")
    func whenModifiersAreStored_thenKeyCodeZeroIsTheAKey() {
        let binding = GlobalShortcut.openShelf.binding(storedKeyCode: 0, storedModifiers: command | shift)

        #expect(binding == HotkeyBinding(keyCode: kVK_ANSI_A, modifiers: UInt32(command | shift)))
    }

    @Test("a stored combination is used as stored")
    func whenCustomStored_thenUsed() {
        let binding = GlobalShortcut.toggleCapture.binding(storedKeyCode: kVK_ANSI_P, storedModifiers: control | option)

        #expect(binding == HotkeyBinding(keyCode: kVK_ANSI_P, modifiers: UInt32(control | option)))
    }

    @Test("every shortcut has its own label, setting keys and Carbon id, and the labels are sentence case")
    func whenListed_thenIdentitiesAreUnique() {
        let all = GlobalShortcut.allCases

        #expect(Set(all.map(\.label)).count == all.count)
        #expect(Set(all.map(\.carbonID)).count == all.count)
        #expect(Set(all.flatMap { [$0.keyCodeSetting.name, $0.modifiersSetting.name] }).count == all.count * 2)
        for shortcut in all {
            let words = shortcut.label.split(separator: " ")
            #expect(words.dropFirst().allSatisfy { $0.first?.isLowercase ?? false }, "\(shortcut.label)")
        }
    }

    @Test("Carbon ids stay clear of the nine pinned slots, which hold 3 to 11")
    func whenIdsAreAssigned_thenPinnedSlotsAreFree() {
        for shortcut in GlobalShortcut.allCases {
            #expect(!(3...11).contains(shortcut.carbonID))
        }
    }

    @Test("every shortcut's keys are in the settings registry, so they are exported and found")
    func whenListed_thenKeysAreRegistered() {
        for shortcut in GlobalShortcut.allCases {
            #expect(Setting.allNames.contains(shortcut.keyCodeSetting.name))
            #expect(Setting.allNames.contains(shortcut.modifiersSetting.name))
        }
    }

    @Test("the binding is read from the preferences a recorder writes")
    func whenRecorded_thenReadBack() {
        let defaults = ThrowawayDefaults.make()
        defaults.set(kVK_ANSI_K, forKey: GlobalShortcut.toggleClipContents.keyCodeSetting.name)
        defaults.set(command | option, forKey: GlobalShortcut.toggleClipContents.modifiersSetting.name)

        #expect(GlobalShortcut.toggleClipContents.binding(in: defaults)
            == HotkeyBinding(keyCode: kVK_ANSI_K, modifiers: UInt32(command | option)))
        #expect(GlobalShortcut.togglePinnedWindow.binding(in: defaults) == nil)
    }

    @Test("the other shortcuts that are set are what a recorder checks a new combination against")
    func whenOthersAreAsked_thenOnlyThoseSetAreListed() {
        let defaults = ThrowawayDefaults.make()
        defaults.set(kVK_ANSI_P, forKey: GlobalShortcut.toggleCapture.keyCodeSetting.name)
        defaults.set(control | option, forKey: GlobalShortcut.toggleCapture.modifiersSetting.name)

        let others = GlobalShortcut.openShelf.others(in: defaults)

        #expect(others.map(\.name).contains("Pause or resume capturing"))
        #expect(!others.map(\.name).contains("Open the shelf"))
        #expect(!others.map(\.name).contains("Show or hide the pinned window"))
        #expect(
            others.count == 2,
            "plain-text paste (a default) and the capture toggle (set); paste-previous has no default"
        )
    }

    @Test("the shelf shortcut as text follows the same rules")
    func whenDescribed_thenDefaultAndCustomRead() {
        #expect(HotkeyDescription.overlay(storedKeyCode: 0, storedModifiers: 0) == "⇧⌘V")
        #expect(HotkeyDescription.overlay(storedKeyCode: 0, storedModifiers: command | shift) == "⇧⌘A")
    }

    @Test("a shortcut that has a default can be turned off, and reads as no shortcut")
    func whenTurnedOff_thenNoBinding() {
        let off = GlobalShortcut.disabledMarker

        #expect(GlobalShortcut.openShelf.binding(storedKeyCode: 0, storedModifiers: off) == nil)
        #expect(GlobalShortcut.pastePlainText.binding(storedKeyCode: kVK_ANSI_V, storedModifiers: off) == nil)
    }

    @Test("the shelf shortcut as text is empty once it is turned off")
    func whenShelfShortcutIsOff_thenNoText() {
        #expect(HotkeyDescription.overlay(storedKeyCode: 0, storedModifiers: GlobalShortcut.disabledMarker).isEmpty)
    }
}

@Suite("Shortcuts macOS already uses")
struct SystemShortcutsTests {
    private let spotlight = HotkeyBinding(keyCode: kVK_Space, modifiers: UInt32(cmdKey))
    private let screenshot = HotkeyBinding(keyCode: kVK_ANSI_3, modifiers: UInt32(cmdKey | shiftKey))

    @Test("a combination in the system's list conflicts, whatever extra flags the system entry carries")
    func whenInTheList_thenConflict() {
        let withFn = HotkeyBinding(keyCode: kVK_Space, modifiers: UInt32(cmdKey) | 0x20000)

        #expect(SystemShortcuts.conflicts(spotlight, in: [withFn]))
        #expect(SystemShortcuts.conflicts(screenshot, in: [spotlight, screenshot]))
    }

    @Test("a different key or different modifiers do not conflict")
    func whenNotInTheList_thenNoConflict() {
        #expect(!SystemShortcuts.conflicts(
            HotkeyBinding(keyCode: kVK_Space, modifiers: UInt32(cmdKey | optionKey)), in: [spotlight]
        ))
        #expect(!SystemShortcuts.conflicts(
            HotkeyBinding(keyCode: kVK_ANSI_4, modifiers: UInt32(cmdKey | shiftKey)), in: [screenshot]
        ))
    }

    @Test("a bare key never conflicts, because system entries without modifiers are not shortcuts to avoid")
    func whenNoModifiers_thenNoConflict() {
        let bare = HotkeyBinding(keyCode: kVK_F1, modifiers: 0)

        #expect(!SystemShortcuts.conflicts(bare, in: [bare]))
    }

    @Test("the recorder refuses a combination macOS has switched on")
    func whenRecordedCombinationIsASystemShortcut_thenTakenBySystem() {
        let outcome = HotkeyRecording.evaluate(
            keyCode: kVK_ANSI_3, modifiers: UInt32(cmdKey | shiftKey), others: [], system: [screenshot]
        )

        #expect(outcome == .takenBySystem)
        #expect(HotkeyRecording.evaluate(
            keyCode: kVK_ANSI_3, modifiers: UInt32(cmdKey | shiftKey | optionKey), others: [], system: [screenshot]
        ) == .accepted)
    }

    @Test("this Mac's own list can be read, and holds only shortcuts with modifiers worth avoiding")
    func whenAskedForTheSystemList_thenItIsReadable() {
        let list = SystemShortcuts.enabledBindings()

        #expect(list.allSatisfy { $0.keyCode >= 0 })
    }
}
