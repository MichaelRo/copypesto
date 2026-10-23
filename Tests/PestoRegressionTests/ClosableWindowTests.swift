// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// A hand-made window that the app keeps a reference to must not be released again by AppKit when it closes: the second
/// release crashed in the next display cycle ("closing Settings quits the app"), and the pinned window had the same
/// shape.
@Suite("Closable windows")
struct ClosableWindowTests {
    @Test("every file that builds a closable NSWindow or NSPanel sets isReleasedWhenClosed = false")
    func closableWindowsAreNotReleasedOnClose() throws {
        var scanned = 0
        var offenders: [String] = []
        for file in try SourceTree.everySwiftFile() {
            scanned += 1
            let text = try String(contentsOf: file, encoding: .utf8)
            let buildsWindow = text.contains("NSPanel(") || text.contains("NSWindow(")
            if buildsWindow, text.contains(".closable"), !text.contains("isReleasedWhenClosed = false") {
                offenders.append(file.lastPathComponent)
            }
        }
        #expect(scanned > 200, "the sources were not found")
        #expect(offenders.isEmpty, "set isReleasedWhenClosed = false: \(offenders)")
    }
}
