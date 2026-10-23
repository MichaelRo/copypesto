// SPDX-License-Identifier: MIT
import Foundation

/// The handshake between a `-UITestMode` app and its runner: the app writes a marker once seeding is
/// complete, and the runner waits for it before interacting. Shared by the app and the runner.
public enum UITestSupport {
    public struct ReadyMarker: Codable, Equatable, Sendable {
        public let seededCount: Int
        public let processID: Int32
    }

    public static let readyFileName = "ready.json"

    public static func readyMarker(in directory: URL) -> ReadyMarker? {
        let url = directory.appendingPathComponent(readyFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ReadyMarker.self, from: data)
    }

    public static let commandLogFileName = "commands.log"

    /// Appends a line to the command log so a failing run shows whether the app received each command.
    public static func appendCommandLog(_ line: String, in directory: URL) {
        let url = directory.appendingPathComponent(commandLogFileName)
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    public static func markReady(
        seededCount: Int,
        processID: Int32 = ProcessInfo.processInfo.processIdentifier,
        in directory: URL
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(ReadyMarker(seededCount: seededCount, processID: processID))
        try data.write(to: directory.appendingPathComponent(readyFileName), options: .atomic)
    }
}
