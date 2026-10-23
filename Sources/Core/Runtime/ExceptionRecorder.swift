// SPDX-License-Identifier: MIT
import Foundation
import os
import Synchronization

/// Objective-C exceptions thrown inside Core Data abort the process with only "abort() called" in the crash
/// report. Recording the reason before the abort is the only way to learn what was thrown.
public enum ExceptionRecorder {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "ExceptionRecorder")
    static let fileName = "last-exception.txt"

    /// The handler is a C function pointer and cannot capture; set once before it is installed.
    private static let directory = Mutex<URL?>(nil)

    public static func report(name: String, reason: String?, callStack: [String], date: Date = .now) -> String {
        let stamp = ISO8601DateFormatter().string(from: date)
        let frames = callStack.prefix(40).joined(separator: "\n")
        // A Core Data reason can quote stored values, so only the first line, cut short, is kept.
        let firstLine = reason?.split(whereSeparator: \.isNewline).first.map { String($0.prefix(160)) }
        return "\(stamp)\n\(name)\n\(firstLine ?? "(no reason)")\n\n\(frames)\n"
    }

    public static func record(report: String, in directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        do {
            try PrivateFile.write(Data(report.utf8), to: url)
        } catch {
            logger.error("exception report write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Part of "Clear everything": the file must not outlive the history it might describe.
    public static func clear(in directory: URL) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
    }

    /// Only a normal launch installs it: a test or UI-test process must never write to the real support directory.
    public static func installIfNormalLaunch() {
        guard LaunchMode.current.usesSystemIntegrations else { return }
        directory.withLock { $0 = AppPaths.supportDirectory }
        NSSetUncaughtExceptionHandler { exception in
            guard let directory = ExceptionRecorder.directory.withLock({ $0 }) else { return }
            ExceptionRecorder.record(
                report: ExceptionRecorder.report(
                    name: exception.name.rawValue,
                    reason: exception.reason,
                    callStack: exception.callStackSymbols
                ),
                in: directory
            )
        }
    }
}
