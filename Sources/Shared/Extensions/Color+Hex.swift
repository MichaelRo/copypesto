// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        switch h.count {
        case 6:
            guard let rgb = UInt64(h, radix: 16) else { return nil }
            self.init(
                red: Double((rgb >> 16) & 0xFF) / 255,
                green: Double((rgb >> 8) & 0xFF) / 255,
                blue: Double(rgb & 0xFF) / 255
            )
        case 8:
            guard let rgba = UInt64(h, radix: 16) else { return nil }
            self.init(
                red: Double((rgba >> 24) & 0xFF) / 255,
                green: Double((rgba >> 16) & 0xFF) / 255,
                blue: Double((rgba >> 8) & 0xFF) / 255,
                opacity: Double(rgba & 0xFF) / 255
            )
        default:
            return nil
        }
    }

    func toHex() -> String? {
        guard let cgColor = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int((cgColor.redComponent * 255).rounded())
        let g = Int((cgColor.greenComponent * 255).rounded())
        let b = Int((cgColor.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

struct HSBColor: Equatable {
    var hue: Double
    var saturation: Double
    var brightness: Double

    init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = min(max(hue, 0), 1)
        self.saturation = min(max(saturation, 0), 1)
        self.brightness = min(max(brightness, 0), 1)
    }

    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0

        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC

        var h = 0.0
        if delta > 0 {
            if maxC == r {
                h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
                if h < 0 { h += 6 }
            } else if maxC == g {
                h = ((b - r) / delta) + 2
            } else {
                h = ((r - g) / delta) + 4
            }
            h /= 6.0
        }
        let s = maxC == 0 ? 0 : (delta / maxC)
        self.init(hue: h, saturation: s, brightness: maxC)
    }

    var color: Color {
        Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    private struct RGBTriplet {
        let red: Double
        let green: Double
        let blue: Double
    }

    var hexString: String {
        let chroma = brightness * saturation
        let hPrime = (hue * 6.0).truncatingRemainder(dividingBy: 6.0)
        let second = chroma * (1.0 - abs(hPrime.truncatingRemainder(dividingBy: 2.0) - 1.0))
        let match = brightness - chroma

        let rgb = switch Int(floor(hPrime)) % 6 {
        case 0: RGBTriplet(red: chroma, green: second, blue: 0)
        case 1: RGBTriplet(red: second, green: chroma, blue: 0)
        case 2: RGBTriplet(red: 0, green: chroma, blue: second)
        case 3: RGBTriplet(red: 0, green: second, blue: chroma)
        case 4: RGBTriplet(red: second, green: 0, blue: chroma)
        default: RGBTriplet(red: chroma, green: 0, blue: second)
        }

        let redByte = Int(((rgb.red + match) * 255.0).rounded())
        let greenByte = Int(((rgb.green + match) * 255.0).rounded())
        let blueByte = Int(((rgb.blue + match) * 255.0).rounded())
        return String(
            format: "%02X%02X%02X",
            min(max(redByte, 0), 255),
            min(max(greenByte, 0), 255),
            min(max(blueByte, 0), 255)
        )
    }
}
