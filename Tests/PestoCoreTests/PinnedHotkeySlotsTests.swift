// SPDX-License-Identifier: MIT
import Carbon.HIToolbox
import Testing
@testable import PestoCore

@MainActor
private final class SpyRegistrar: SlotHotkeyRegistering {
    var registered: Set<Int> = []
    var refuse: Set<Int> = []
    private(set) var registerCalls: [Int] = []

    func register(slot: Int) -> Bool {
        registerCalls.append(slot)
        guard !refuse.contains(slot) else { return false }
        registered.insert(slot)
        return true
    }

    func unregister(slot: Int) {
        registered.remove(slot)
    }
}

@Suite("Pinned slots macOS already uses")
struct PinnedHotkeySystemSlotsTests {
    private let digits = [
        kVK_ANSI_1,
        kVK_ANSI_2,
        kVK_ANSI_3,
        kVK_ANSI_4,
        kVK_ANSI_5,
        kVK_ANSI_6,
        kVK_ANSI_7,
        kVK_ANSI_8,
        kVK_ANSI_9
    ]

    @Test("a slot whose ⌃ digit is a switched-on system shortcut is taken, and the others are not")
    func whenMissionControlOwnsTwoDesktops_thenThoseSlotsAreTaken() {
        let system = [
            HotkeyBinding(keyCode: kVK_ANSI_1, modifiers: UInt32(controlKey)),
            HotkeyBinding(keyCode: kVK_ANSI_2, modifiers: UInt32(controlKey)),
            HotkeyBinding(keyCode: kVK_ANSI_3, modifiers: UInt32(controlKey | shiftKey))
        ]

        #expect(PinnedHotkeySlots.systemTaken(by: system, slotKeyCodes: digits) == [1, 2])
    }

    @Test("with nothing of the system's on those keys, no slot is taken")
    func whenSystemListIsEmpty_thenNothingIsTaken() {
        #expect(PinnedHotkeySlots.systemTaken(by: [], slotKeyCodes: digits).isEmpty)
    }
}

@Suite("PinnedHotkeySlots")
@MainActor
struct PinnedHotkeySlotsTests {
    @Test("with no assigned slots nothing is registered, so no ⌃N is stolen from other apps")
    func whenNoSlots_thenNothingRegistered() {
        let registrar = SpyRegistrar()
        var slots = PinnedHotkeySlots()

        slots.update(active: [], using: registrar)

        #expect(registrar.registerCalls.isEmpty)
    }

    @Test("only the assigned slots are registered")
    func whenSlotsAssigned_thenOnlyThoseRegistered() {
        let registrar = SpyRegistrar()
        var slots = PinnedHotkeySlots()

        slots.update(active: [2, 5], using: registrar)

        #expect(registrar.registered == [2, 5])
    }

    @Test("a slot that is unassigned is unregistered")
    func whenSlotRemoved_thenUnregistered() {
        let registrar = SpyRegistrar()
        var slots = PinnedHotkeySlots()
        slots.update(active: [2, 5], using: registrar)

        slots.update(active: [5], using: registrar)

        #expect(registrar.registered == [5])
    }

    @Test("an unchanged set registers nothing again")
    func whenUnchanged_thenNoReRegistration() {
        let registrar = SpyRegistrar()
        var slots = PinnedHotkeySlots()
        slots.update(active: [3], using: registrar)

        slots.update(active: [3], using: registrar)

        #expect(registrar.registerCalls == [3])
    }

    @Test("a slot another app owns is reported unavailable")
    func whenRegistrationRefused_thenUnavailable() {
        let registrar = SpyRegistrar()
        registrar.refuse = [4]
        var slots = PinnedHotkeySlots()

        slots.update(active: [4, 6], using: registrar)

        #expect(slots.unavailable == [4])
        #expect(registrar.registered == [6])
    }

    @Test("slots outside 1 to 9 are ignored")
    func whenSlotOutOfRange_thenIgnored() {
        let registrar = SpyRegistrar()
        var slots = PinnedHotkeySlots()

        slots.update(active: [0, 10, 3], using: registrar)

        #expect(registrar.registered == [3])
    }
}

@Suite("Warning about a pinned shortcut that another app holds")
struct PinnedHotkeyWarningTests {
    @Test("nothing is said when every shortcut registered")
    func none() {
        #expect(PinnedHotkeyWarning.message(for: []) == nil)
    }

    @Test("one taken slot is named")
    func one() throws {
        let message = try #require(PinnedHotkeyWarning.message(for: [3]))
        #expect(message.contains("⌃3 is taken by another app"))
    }

    @Test("several taken slots are listed in order")
    func several() throws {
        let message = try #require(PinnedHotkeyWarning.message(for: [5, 2]))
        #expect(message.contains("⌃2 and ⌃5 are taken by other apps"))
    }

    @Test("only slots not warned about yet are reported, and a freed slot can be warned about again")
    func fresh() {
        var warned: Set<Int> = []

        #expect(PinnedHotkeyWarning.fresh(unavailable: [2, 5], warned: &warned) == [2, 5])
        #expect(PinnedHotkeyWarning.fresh(unavailable: [2, 5], warned: &warned).isEmpty)
        #expect(PinnedHotkeyWarning.fresh(unavailable: [5], warned: &warned).isEmpty)
        #expect(PinnedHotkeyWarning.fresh(unavailable: [2, 5], warned: &warned) == [2])
    }

    @MainActor
    @Test("a slot another app took while Pesto's shortcuts were paused is no longer ours and shows as unavailable")
    func whenSlotIsLostAfterAPause_thenItMovesToUnavailable() {
        let registrar = SpyRegistrar()
        var slots = PinnedHotkeySlots()
        slots.update(active: [2, 4], using: registrar)

        slots.markUnavailable(4)

        #expect(slots.registered == [2])
        #expect(slots.unavailable == [4])
    }
}
