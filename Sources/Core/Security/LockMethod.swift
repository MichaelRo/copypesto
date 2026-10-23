// SPDX-License-Identifier: MIT
import LocalAuthentication

public struct LockMethod: Equatable, Sendable {
    public let biometryType: LABiometryType

    public init(biometryType: LABiometryType) {
        self.biometryType = biometryType
    }

    /// `biometryType` is only populated after the policy has been evaluated for availability.
    public static func current() -> LockMethod {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        return LockMethod(biometryType: context.biometryType)
    }

    public var name: String {
        switch biometryType {
        case .touchID: "Touch ID"
        case .faceID: "Face ID"
        case .opticID: "Optic ID"
        default: "your password"
        }
    }

    public var symbolName: String {
        switch biometryType {
        case .touchID: "touchid"
        case .faceID: "faceid"
        case .opticID: "opticid"
        default: "lock.fill"
        }
    }

    public var unlockTitle: String {
        "Unlock with \(name)"
    }

    public var settingsToggleTitle: String {
        "Lock history with \(name)"
    }
}
