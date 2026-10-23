// SPDX-License-Identifier: MIT
import Carbon.HIToolbox

@MainActor
public protocol SlotHotkeyRegistering {
    func register(slot: Int) -> Bool
    func unregister(slot: Int)
}

/// Global ⌃1–⌃9 shortcuts are claimed only while a pinned item is assigned to the slot; registering all nine
/// unconditionally took them from every other app.
public struct PinnedHotkeySlots: Sendable {
    public private(set) var registered: Set<Int> = []
    public private(set) var unavailable: Set<Int> = []

    public init() {}

    /// The slots (1-based) whose ⌃N macOS itself has switched on, for example Mission Control's Switch to Desktop N.
    /// A Carbon hotkey for one of them registers without an error and then never fires, so it counts as taken.
    public static func systemTaken(by systemList: [HotkeyBinding], slotKeyCodes: [Int]) -> Set<Int> {
        Set(slotKeyCodes.indices.filter { index in
            SystemShortcuts.conflicts(
                HotkeyBinding(keyCode: slotKeyCodes[index], modifiers: UInt32(controlKey)), in: systemList
            )
        }.map { $0 + 1 })
    }

    /// A slot whose shortcut another app took while Pesto's were paused: it is no longer ours, and shows as
    /// unavailable.
    public mutating func markUnavailable(_ slot: Int) {
        registered.remove(slot)
        unavailable.insert(slot)
    }

    @MainActor
    public mutating func update(active: Set<Int>, using registrar: some SlotHotkeyRegistering) {
        let wanted = active.filter { (1...9).contains($0) }
        for slot in registered.subtracting(wanted) {
            registrar.unregister(slot: slot)
            registered.remove(slot)
        }
        unavailable.formIntersection(wanted)
        for slot in wanted.subtracting(registered).subtracting(unavailable).sorted() {
            if registrar.register(slot: slot) {
                registered.insert(slot)
            } else {
                unavailable.insert(slot)
            }
        }
    }
}
