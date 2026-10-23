// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI
import Testing
@testable import Pesto

@Suite("Status colors")
@MainActor
struct StatusColorsTests {
    private func hex(of color: Color, appearance: NSAppearance.Name) throws -> String {
        var result = ""
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .black
            result = String(
                format: "%02X%02X%02X", Int((resolved.redComponent * 255).rounded()),
                Int((resolved.greenComponent * 255).rounded()), Int((resolved.blueComponent * 255).rounded())
            )
        }
        return result
    }

    @Test("the solid destructive fill is the one Core tests for contrast")
    func fillMatchesCore() throws {
        #expect(try hex(of: .statusBadFill, appearance: .aqua) == DestructiveFill.lightHex)
        #expect(try hex(of: .statusBadFill, appearance: .darkAqua) == DestructiveFill.darkHex)
    }
}
