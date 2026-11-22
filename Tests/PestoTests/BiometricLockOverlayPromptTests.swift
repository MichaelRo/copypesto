// SPDX-License-Identifier: MIT
import LocalAuthentication
import PestoCore
import SwiftUI
import Testing
@testable import Pesto

@Suite("BiometricLockOverlay shelf prompt icon")
@MainActor
struct BiometricLockOverlayPromptTests {
    @Test("uses lock.fill instead of a duplicate touchid SF Symbol when embedded Touch ID prompt is shown")
    func whenEmbeddedPromptAndTouchID_thenUsesLockFill() {
        let symbol = BiometricLockOverlay<EmptyView>.shelfPromptSymbolName(
            usesEmbeddedPrompt: true,
            lockMethod: LockMethod(biometryType: .touchID)
        )
        #expect(symbol == "lock.fill")
    }

    @Test("keeps lock method symbol when embedded Touch ID prompt is not active or biometry is not Touch ID")
    func whenNotEmbeddedOrOtherBiometry_thenUsesLockMethodSymbol() {
        #expect(
            BiometricLockOverlay<EmptyView>.shelfPromptSymbolName(
                usesEmbeddedPrompt: false,
                lockMethod: LockMethod(biometryType: .touchID)
            ) == "touchid"
        )
        #expect(
            BiometricLockOverlay<EmptyView>.shelfPromptSymbolName(
                usesEmbeddedPrompt: true,
                lockMethod: LockMethod(biometryType: .faceID)
            ) == "faceid"
        )
        #expect(
            BiometricLockOverlay<EmptyView>.shelfPromptSymbolName(
                usesEmbeddedPrompt: true,
                lockMethod: LockMethod(biometryType: .none)
            ) == "lock.fill"
        )
    }
}
