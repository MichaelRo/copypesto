// SPDX-License-Identifier: MIT
import Foundation
import LocalAuthentication

/// What this iPhone or iPad asks for: Face ID, Touch ID, Optic ID, or the passcode when it has no biometrics. The Mac's
/// `LockMethod` says "your password", which an iPhone does not have.
enum DeviceAuthenticationWords {
    static func biometry() -> LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    static func name(for biometry: LABiometryType) -> String {
        switch biometry {
        case .faceID: String(localized: "Face ID")
        case .touchID: String(localized: "Touch ID")
        case .opticID: String(localized: "Optic ID")
        default: String(localized: "your passcode")
        }
    }

    static func symbol(for biometry: LABiometryType) -> String {
        switch biometry {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        default: "lock.fill"
        }
    }

    static func lockToggleTitle(for biometry: LABiometryType) -> String {
        String(localized: "Lock history with \(name(for: biometry))")
    }

    static func unlockTitle(for biometry: LABiometryType) -> String {
        String(localized: "Unlock with \(name(for: biometry))")
    }

    static func graceTitle(for biometry: LABiometryType) -> String {
        switch biometry {
        case .faceID: String(localized: "Ask for Face ID again after")
        case .touchID: String(localized: "Ask for Touch ID again after")
        case .opticID: String(localized: "Ask for Optic ID again after")
        default: String(localized: "Ask for the passcode again after")
        }
    }
}
