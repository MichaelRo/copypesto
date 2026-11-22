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
    private static let slowMainActorThreshold = Duration.milliseconds(25)
    private static let logFileURL: URL? = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)
        .first?
        .appendingPathComponent("hang-diagnostics.log")

    @MainActor private var isStarted = false
    private var watchdogTask: Task<Void, Never>?

    @MainActor
    func start() {
        guard !isStarted else { return }
        isStarted = true
        #if canImport(MetricKit) && !targetEnvironment(simulator)
        MXMetricManager.shared.add(self)
        #endif
        startWatchdog()
    }

    private func startWatchdog() {
        watchdogTask = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                let pingStart = ContinuousClock.now
                await MainActor.run {
                    let delay = ContinuousClock.now - pingStart
                    if delay >= .milliseconds(80) {
                        let ms = Int(delay.components.seconds * 1000)
                            + Int(delay.components.attoseconds / 1_000_000_000_000_000)
                        Self.record("Main-thread stall detected: \(ms) ms")
                    }
                }
            }
        }
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
                record("Slow main-actor work (\(label)): \(ms) ms")
            }
        }
        return try operation()
    }

    private static func record(_ message: String) {
        logger.warning("\(message, privacy: .public)")
        guard let url = logFileURL else { return }
        let line = "\(ISO8601DateFormatter().string(from: .now)) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
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
