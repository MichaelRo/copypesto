// SPDX-License-Identifier: MIT
import AppKit

extension Data {
    func convertedToPNG() -> Data? {
        NSBitmapImageRep(data: self)?.representation(using: .png, properties: [:])
    }
}
