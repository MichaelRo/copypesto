// SPDX-License-Identifier: MIT
import Foundation
#if canImport(MetricKit)
import MetricKit
#endif
import os
import PestoCore

/// Subscribes to iOS hang diagnostics (`MetricKit`) and logs slow main-actor operations to OSLog so field-test freezes
/// can be inspected in Console / Xcode Organizer without telemetry or third-party SDKs.
final class HangDiagnostics: NSObject, @unchecked Sendable {
    static let shared = HangDiagnostics()

    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Hangs")
    private static let signposter = OSSignposter(logger: logger)
    private static let slowMainActorThreshold = Duration.milliseconds(100)

    @MainActor private var isStarted = false

    @MainActor
    func start() {
        guard !isStarted else { return }
        isStarted = true
        #if canImport(MetricKit) && !targetEnvironment(simulator)
        MXMetricManager.shared.add(self)
        #endif
    }

    @MainActor
    @discardableResult
    static func measure<T>(_ label: StaticString, operation: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(label)
        let start = ContinuousClock.now
        defer {
            signposter.endInterval(label, state)
            let elapsed = ContinuousClock.now - start
            if elapsed >= slowMainActorThreshold {
                let ms = Int(elapsed.components.seconds * 1000)
                    + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
                logger.warning("Slow main-actor work (\(label, privacy: .public)): \(ms) ms")
            }
        }
        return try operation()
    }
}

#if canImport(MetricKit) && !targetEnvironment(simulator)
extension HangDiagnostics: MXMetricManagerSubscriber {
    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            guard let hangs = payload.hangDiagnostics, !hangs.isEmpty else { continue }
            for hang in hangs {
                let duration = hang.hangDuration.converted(to: .milliseconds).value
                let tree = String(data: hang.callStackTree.jsonRepresentation(), encoding: .utf8) ?? ""
                Self.logger.error(
                    "MXHangDiagnostic (\(Int(duration)) ms): \(tree.prefix(1500), privacy: .public)"
                )
            }
        }
    }
}
#endif
