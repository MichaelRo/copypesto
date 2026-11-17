// SPDX-License-Identifier: MIT
import Foundation
import LocalAuthentication

public protocol LAContextEvaluating {
    func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool
    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String) async throws -> Bool
}

extension LAContext: LAContextEvaluating {}
