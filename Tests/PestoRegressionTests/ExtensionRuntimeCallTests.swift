// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// App Review guideline 2.5.1 (ADR 0072): an extension calls APIs as Swift declares them, never through a selector
/// built from a string or a method looked up at run time, which reads as hiding a private API.
@Suite("Extensions call APIs only as declared")
struct ExtensionRuntimeCallTests {
    private static let runtimeCalls = [
        "NSSelectorFromString", "class_getInstanceMethod", "method_getImplementation", "unsafeBitCast(method",
        "perform(Selector", "objc_msgSend"
    ]

    @Test("no extension builds a selector from a string or calls a method it looked up")
    func whenScanningExtensions_thenNoRuntimeCalls() throws {
        var offenders: [String] = []
        for folder in ["MobileKeyboard", "MobileAutoFill", "MobileShare", "MobileWidget", "MobileShared", "Widget"] {
            for file in try SourceTree.swiftFiles(in: folder, minimum: 1) {
                let text = try String(contentsOf: file, encoding: .utf8)
                for call in Self.runtimeCalls where text.contains(call) {
                    offenders.append("\(file.lastPathComponent): \(call)")
                }
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }
}
