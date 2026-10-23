// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import PestoCore

@Suite("SoundEffectPolicy")
struct SoundEffectPolicyTests {
    @Test("sounds are off by default and play only when the user turned them on")
    func onlyWhenEnabled() {
        #expect(!SoundEffectPolicy.shouldPlay(enabled: false, systemIntegrations: true))
        #expect(SoundEffectPolicy.shouldPlay(enabled: true, systemIntegrations: true))
    }

    @Test("never under test, so a test run is silent")
    func silentUnderTest() {
        #expect(!SoundEffectPolicy.shouldPlay(enabled: true, systemIntegrations: false))
    }

    @Test("a paste that needed a manual ⌘V does not play the paste sound")
    func manualPasteIsSilent() {
        #expect(SoundEffectPolicy.pasteSoundFor(outcomeRequiredManualPaste: false))
        #expect(!SoundEffectPolicy.pasteSoundFor(outcomeRequiredManualPaste: true))
    }

    @Test("copy and paste synthesized tones produce valid, distinct WAV buffers that NSSound can play")
    func whenSynthesizedTones_thenValidWAVAndLoadableByNSSound() throws {
        let copyData = SoundEffectPolicy.wavData(for: .copy)
        let pasteData = SoundEffectPolicy.wavData(for: .paste)

        #expect(copyData != pasteData)
        #expect(String(data: copyData.prefix(4), encoding: .ascii) == "RIFF")
        #expect(String(data: pasteData.prefix(4), encoding: .ascii) == "RIFF")

        let copySound = try #require(NSSound(data: copyData))
        let pasteSound = try #require(NSSound(data: pasteData))
        #expect(copySound.duration > 0.04 && copySound.duration < 0.15)
        #expect(pasteSound.duration > 0.04 && pasteSound.duration < 0.15)
    }

    @Test("every theme synthesizes distinct, valid tones for copy and paste")
    func whenThemedTones_thenDistinctAndValidAcrossThemes() throws {
        var copyBuffers: [AppTheme: Data] = [:]
        for theme in AppTheme.allCases {
            let copy = SoundEffectPolicy.wavData(for: .copy, theme: theme)
            let paste = SoundEffectPolicy.wavData(for: .paste, theme: theme)

            #expect(copy != paste)
            let copySound = try #require(NSSound(data: copy))
            let pasteSound = try #require(NSSound(data: paste))
            #expect(copySound.duration > 0.03 && copySound.duration < 0.15)
            #expect(pasteSound.duration > 0.03 && pasteSound.duration < 0.15)

            copyBuffers[theme] = copy
        }

        // Each theme has its own distinct acoustic wave
        let uniqueBuffers = Set(copyBuffers.values)
        #expect(uniqueBuffers.count == AppTheme.allCases.count)
    }
}
