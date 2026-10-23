// SPDX-License-Identifier: MIT
import Foundation

public enum CLIInstall {
    /// `pesto install` links the tool into /usr/local/bin. It may replace its own earlier link but must never delete
    /// some other file that happens to sit at that path.
    public static func mayReplace(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return true }
        return attributes[.type] as? FileAttributeType == .typeSymbolicLink
    }

    /// A fresh Apple silicon Mac has no `/usr/local/bin`, and an ordinary account cannot write it, so the link goes
    /// there only when it can be made and otherwise into `~/.local/bin`.
    public static func linkFolder(shared: URL, sharedIsWritable: Bool, home: URL) -> URL {
        sharedIsWritable ? shared : home.appendingPathComponent(".local/bin", isDirectory: true)
    }
}
