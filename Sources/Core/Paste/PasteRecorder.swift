// SPDX-License-Identifier: MIT
import Foundation

/// Stands in for the real paste (focus restore, Accessibility write, ⌘V) under UI test: it appends what
/// would have been pasted to a JSON-lines file that the test runner reads back.
public struct PasteRecorder: Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let kind: String
        public let text: String?
    }

    public let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("paste-log.jsonl")
    }

    public static func make(for configuration: RuntimeConfiguration, temporary: URL) -> PasteRecorder? {
        guard configuration.mode == .uiTest, !configuration.usesRealPasteboard else { return nil }
        let directory = AppPaths.supportDirectory(
            for: configuration,
            applicationSupport: temporary,
            temporary: temporary
        )
        return PasteRecorder(directory: directory)
    }

    public static var current: PasteRecorder? {
        make(for: RuntimeConfiguration.current, temporary: FileManager.default.temporaryDirectory)
    }

    public func record(_ payload: PasteCoordinator.PayloadKind) {
        let entry = switch payload {
        case let .text(text), let .richText(text): Entry(kind: "text", text: text)
        case .nonText: Entry(kind: "nonText", text: nil)
        }
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var line = data
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: fileURL)
        }
    }

    public func entries() -> [Entry] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return content.split(separator: "\n").compactMap { try? JSONDecoder().decode(Entry.self, from: Data($0.utf8)) }
    }
}
