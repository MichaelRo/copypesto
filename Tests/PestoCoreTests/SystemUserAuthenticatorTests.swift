// SPDX-License-Identifier: MIT
import Foundation
import LocalAuthentication
import Synchronization
import Testing
@testable import PestoCore

private final class FakeLAContext: LAContextEvaluating, Sendable {
    let canEvaluateResult: Bool
    let canEvaluateError: LAError.Code?
    let evaluateResult: Result<Bool, Error>
    let recordedPolicies = Mutex<[LAPolicy]>([])
    let recordedReasons = Mutex<[String]>([])

    init(
        canEvaluateResult: Bool = true,
        canEvaluateError: LAError.Code? = nil,
        evaluateResult: Result<Bool, Error> = .success(true)
    ) {
        self.canEvaluateResult = canEvaluateResult
        self.canEvaluateError = canEvaluateError
        self.evaluateResult = evaluateResult
    }

    func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
        recordedPolicies.withLock { $0.append(policy) }
        if let canEvaluateError {
            error?.pointee = NSError(domain: LAError.errorDomain, code: canEvaluateError.rawValue)
        }
        return canEvaluateResult
    }

    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String) async throws -> Bool {
        recordedPolicies.withLock { $0.append(policy) }
        recordedReasons.withLock { $0.append(localizedReason) }
        return try evaluateResult.get()
    }
}

@Suite("SystemUserAuthenticator")
struct SystemUserAuthenticatorTests {
    @Test("uses deviceOwnerAuthentication for availability and evaluation")
    func whenEvaluating_thenUsesDeviceOwnerAuthentication() async {
        let context = FakeLAContext(canEvaluateResult: true, evaluateResult: .success(true))
        let auth = SystemUserAuthenticator { context }

        #expect(auth.canAuthenticate())
        let ok = await auth.authenticate(reason: "Unlock")
        #expect(ok)
        #expect(context.recordedPolicies.withLock { $0 } == [.deviceOwnerAuthentication, .deviceOwnerAuthentication])
        #expect(context.recordedReasons.withLock { $0 } == ["Unlock"])
    }

    @Test("biometryLockout with deviceOwnerAuthentication still allows password fallback when canEvaluate is true")
    func whenBiometryLockout_thenDeviceOwnerFallbackAvailable() async {
        let context = FakeLAContext(
            canEvaluateResult: true,
            canEvaluateError: .biometryLockout,
            evaluateResult: .success(true)
        )
        let auth = SystemUserAuthenticator { context }

        #expect(auth.canAuthenticate())
        #expect(await auth.authenticate(reason: "Unlock"))
        #expect(!HistoryLockPolicy.shouldRetryBiometric(errorCode: LAError.biometryLockout.rawValue, attempt: 0))
    }

    @Test("passcodeNotSet reports unavailable")
    func whenPasscodeNotSet_thenUnavailable() {
        let context = FakeLAContext(canEvaluateResult: false, canEvaluateError: .passcodeNotSet)
        let auth = SystemUserAuthenticator { context }

        #expect(!auth.canAuthenticate())
        #expect(auth.availability == .unavailable)
    }

    @Test("userCancel and systemCancel return false from authenticate; only systemCancel is retried")
    func whenUserCancelVsSystemCancel_thenRetryPolicyDiffers() async {
        let userCancel = SystemUserAuthenticator {
            FakeLAContext(evaluateResult: .failure(LAError(.userCancel)))
        }
        let systemCancel = SystemUserAuthenticator {
            FakeLAContext(evaluateResult: .failure(LAError(.systemCancel)))
        }

        #expect(await !(userCancel.authenticate(reason: "Unlock")))
        #expect(await !(systemCancel.authenticate(reason: "Unlock")))
        #expect(!HistoryLockPolicy.shouldRetryBiometric(errorCode: LAError.userCancel.rawValue, attempt: 0))
        #expect(HistoryLockPolicy.shouldRetryBiometric(errorCode: LAError.systemCancel.rawValue, attempt: 0))
    }
}
