// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The foot glow: a hint of the source app's color at a card's foot")
struct CardGlowTests {
    private func glow(_ hex: String?, dark: Bool = false, glass: Bool = false) -> CardGlow? {
        CardGlow.decide(colorHex: hex, isDark: dark, isGlass: glass, increaseContrast: false, isSelected: false)
    }

    @Test("opacity follows the appearance and the shelf's surface")
    func whenSurfaceDiffers_thenOpacityFollows() throws {
        let safari = "#1796F2"
        #expect(try #require(glow(safari)).opacity == 0.11)
        #expect(try #require(glow(safari, dark: true)).opacity == 0.16)
        #expect(try #require(glow(safari, glass: true)).opacity == 0.08)
        #expect(try #require(glow(safari, dark: true, glass: true)).opacity == 0.12)
        let selected = CardGlow.decide(
            colorHex: safari, isDark: false, isGlass: false, increaseContrast: false, isSelected: true
        )
        #expect(try #require(selected).opacity == 0.11 * 0.6)
    }

    @Test("greens near basil and yellows near gold are muted, so color never says focus or collection")
    func whenHueNearTheBrand_thenMuted() throws {
        let messages = try #require(glow("#44DC5D"))
        let notes = try #require(glow("#FAD927"))
        let safari = try #require(glow("#1796F2"))
        #expect(messages.chroma <= 0.05 + 1e-9 && notes.chroma <= 0.05 + 1e-9)
        #expect(messages.opacity < safari.opacity && notes.opacity < safari.opacity)
        #expect(safari.chroma <= 0.12 + 1e-9)
    }

    @Test("a near-black, near-white or grey icon, no color, a bad value or Increase Contrast draw no glow")
    func whenNeutralOrOff_thenNone() {
        #expect(glow("#1D1D1D") == nil)
        #expect(glow("#888888") == nil)
        #expect(glow("#FAFAFA") == nil)
        #expect(glow(nil) == nil)
        #expect(glow("red") == nil)
        #expect(CardGlow.decide(
            colorHex: "#1796F2", isDark: false, isGlass: false, increaseContrast: true, isSelected: false
        ) == nil)
    }

    @Test("text stays readable over the strongest glow of every hue, in both appearances")
    func whenAnyHue_thenTextKeepsItsContrast() throws {
        for degrees in stride(from: 0.0, to: 360.0, by: 5.0) {
            let hex = CardGlow.hex(lightness: 0.65, chroma: 0.2, hue: degrees)
            for dark in [false, true] {
                guard let glow = glow(hex, dark: dark) else { continue }
                let card = dark ? "353936" : "FFFFFF"
                let ground = try #require(glow.blended(over: card))
                let ink = dark ? "F6EFD9" : "2B2F2A"
                let muted = dark ? "B5B9AB" : "4F544C"
                #expect(ContrastRatio.between(ink, ground) >= 7, "ink \(hex) dark \(dark)")
                #expect(ContrastRatio.between(muted, ground) >= 4.5, "muted \(hex) dark \(dark)")
            }
        }
    }
}
