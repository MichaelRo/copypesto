// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("LockMethod")
struct LockMethodTests {
    @Test("names follow the biometry the Mac has")
    func namesFollowBiometry() {
        #expect(LockMethod(biometryType: .touchID).name == "Touch ID")
        #expect(LockMethod(biometryType: .faceID).name == "Face ID")
        #expect(LockMethod(biometryType: .opticID).name == "Optic ID")
    }

    @Test("a Mac without biometrics falls back to the account password")
    func whenNoBiometry_thenPassword() {
        let method = LockMethod(biometryType: .none)

        #expect(method.name == "your password")
        #expect(method.symbolName == "lock.fill")
    }

    @Test("the unlock label and settings label read naturally for each method")
    func labels() {
        #expect(LockMethod(biometryType: .touchID).unlockTitle == "Unlock with Touch ID")
        #expect(LockMethod(biometryType: .none).unlockTitle == "Unlock with your password")
        #expect(LockMethod(biometryType: .touchID).settingsToggleTitle == "Lock history with Touch ID")
        #expect(LockMethod(biometryType: .none).settingsToggleTitle == "Lock history with your password")
    }

    @Test("symbols match the biometry")
    func symbols() {
        #expect(LockMethod(biometryType: .touchID).symbolName == "touchid")
        #expect(LockMethod(biometryType: .faceID).symbolName == "faceid")
        #expect(LockMethod(biometryType: .opticID).symbolName == "opticid")
    }
}
