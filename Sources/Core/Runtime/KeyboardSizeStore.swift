// SPDX-License-Identifier: MIT
import Foundation

/// Persists the chosen `KeyboardSize` in the shared app group so `PestoKeyboard` and `KeyboardSettingsView` stay in
/// sync without waiting for the host app to rewrite the quick-insert set.
public struct KeyboardSizeStore: Sendable {
    public struct Record: Codable, Equatable, Sendable {
        public let size: KeyboardSize
        public let updatedAt: Date

        public init(size: KeyboardSize, updatedAt: Date = .now) {
            self.size = size
            self.updatedAt = updatedAt
        }
    }

    public static let fileName = "keyboard-size.json"

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static var current: KeyboardSizeStore? {
        guard LaunchMode.current != .hostedTests else { return nil }
        return AppPaths.sharedGroupDirectory.map(Self.init(root:))
    }

    public var url: URL {
        root.appendingPathComponent(Self.fileName)
    }

    public func load() -> Record? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    public func save(_ size: KeyboardSize, at date: Date = .now) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Record(size: size, updatedAt: date))
        try PrivateFile.write(data, to: url)
    }
}
