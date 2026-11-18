// SPDX-License-Identifier: MIT
#if os(macOS)
import AppKit

extension Data {
    func convertedToPNG() -> Data? {
        NSBitmapImageRep(data: self)?.representation(using: .png, properties: [:])
    }
}
#endif
