// SPDX-License-Identifier: MIT
import Foundation

public enum SoundEffectPolicy {
    public enum Tone: Sendable {
        case copy
        case paste
    }

    public static let defaultsKey = "soundEffectsEnabled"

    public static func shouldPlay(enabled: Bool, systemIntegrations: Bool) -> Bool {
        enabled && systemIntegrations
    }

    public static func pasteSoundFor(outcomeRequiredManualPaste: Bool) -> Bool {
        !outcomeRequiredManualPaste
    }

    private struct NoteSpec {
        let start: Double
        let duration: Double
        let frequency: Double
        let decay: Double
        let gain: Double
    }

    public static func wavData(for tone: Tone, theme: AppTheme = .basil) -> Data {
        let sampleRate = 44_100
        let duration = duration(for: tone, theme: theme)
        let sampleCount = Int(Double(sampleRate) * duration)
        var pcm = Data(capacity: sampleCount * 2)
        let specs = noteSpecs(for: tone, theme: theme)

        for i in 0..<sampleCount {
            let t = Double(i) / Double(sampleRate)
            var sample = 0.0
            for spec in specs {
                sample += noteSample(time: t, spec: spec)
            }
            let clamped = max(-1.0, min(1.0, sample))
            var intSample = Int16(clamped * Double(Int16.max)).littleEndian
            withUnsafeBytes(of: &intSample) { pcm.append(contentsOf: $0) }
        }

        return encodeWAVHeader(pcmBytes: pcm, sampleRate: UInt32(sampleRate))
    }

    private static func duration(for tone: Tone, theme: AppTheme) -> Double {
        switch theme {
        case .basil: tone == .copy ? 0.070 : 0.080
        case .parmesan: tone == .copy ? 0.055 : 0.065
        case .pineNut: tone == .copy ? 0.080 : 0.090
        case .mortar: tone == .copy ? 0.090 : 0.100
        }
    }

    private static func noteSpecs(for tone: Tone, theme: AppTheme) -> [NoteSpec] {
        switch (theme, tone) {
        case (.basil, .copy):
            [
                NoteSpec(start: 0.0, duration: 0.032, frequency: 523.25, decay: 58.0, gain: 0.18),
                NoteSpec(start: 0.018, duration: 0.052, frequency: 659.25, decay: 48.0, gain: 0.20)
            ]
        case (.basil, .paste):
            [
                NoteSpec(start: 0.0, duration: 0.030, frequency: 587.33, decay: 58.0, gain: 0.17),
                NoteSpec(start: 0.018, duration: 0.062, frequency: 440.00, decay: 44.0, gain: 0.21)
            ]
        case (.parmesan, .copy):
            [
                NoteSpec(start: 0.0, duration: 0.024, frequency: 783.99, decay: 80.0, gain: 0.17),
                NoteSpec(start: 0.012, duration: 0.040, frequency: 987.77, decay: 70.0, gain: 0.19)
            ]
        case (.parmesan, .paste):
            [
                NoteSpec(start: 0.0, duration: 0.024, frequency: 659.25, decay: 75.0, gain: 0.16),
                NoteSpec(start: 0.012, duration: 0.050, frequency: 523.25, decay: 65.0, gain: 0.20)
            ]
        case (.pineNut, .copy):
            [
                NoteSpec(start: 0.0, duration: 0.038, frequency: 392.00, decay: 45.0, gain: 0.20),
                NoteSpec(start: 0.020, duration: 0.058, frequency: 493.88, decay: 40.0, gain: 0.22)
            ]
        case (.pineNut, .paste):
            [
                NoteSpec(start: 0.0, duration: 0.036, frequency: 440.00, decay: 45.0, gain: 0.19),
                NoteSpec(start: 0.020, duration: 0.068, frequency: 329.63, decay: 38.0, gain: 0.23)
            ]
        case (.mortar, .copy):
            [
                NoteSpec(start: 0.0, duration: 0.045, frequency: 220.00, decay: 35.0, gain: 0.24),
                NoteSpec(start: 0.022, duration: 0.068, frequency: 277.18, decay: 30.0, gain: 0.26)
            ]
        case (.mortar, .paste):
            [
                NoteSpec(start: 0.0, duration: 0.042, frequency: 246.94, decay: 35.0, gain: 0.22),
                NoteSpec(start: 0.022, duration: 0.076, frequency: 164.81, decay: 26.0, gain: 0.28)
            ]
        }
    }

    private static func noteSample(time: Double, spec: NoteSpec) -> Double {
        let local = time - spec.start
        guard local >= 0, local < spec.duration else { return 0 }
        let attackTime = 0.0035
        let releaseTime = 0.006
        let attack = local < attackTime ? 0.5 * (1.0 - cos(.pi * local / attackTime)) : 1.0
        let remaining = spec.duration - local
        let release = remaining < releaseTime ? 0.5 * (1.0 - cos(.pi * remaining / releaseTime)) : 1.0
        let envelope = attack * release * exp(-local * spec.decay)
        let fundamental = sin(2.0 * .pi * spec.frequency * local)
        let overtone = 0.15 * sin(2.0 * .pi * (spec.frequency * 2.0) * local)
        return spec.gain * envelope * (fundamental + overtone)
    }

    private static func encodeWAVHeader(pcmBytes: Data, sampleRate: UInt32) -> Data {
        let dataSize = UInt32(pcmBytes.count)
        let riffChunkSize = 36 + dataSize
        let byteRate = sampleRate * 2
        let blockAlign: UInt16 = 2
        let bitsPerSample: UInt16 = 16
        let audioFormatPCM: UInt16 = 1
        let numChannels: UInt16 = 1
        let fmtChunkSize: UInt32 = 16

        var data = Data(capacity: 44 + pcmBytes.count)
        data.append(contentsOf: "RIFF".utf8)
        appendLittleEndian(riffChunkSize, to: &data)
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        appendLittleEndian(fmtChunkSize, to: &data)
        appendLittleEndian(audioFormatPCM, to: &data)
        appendLittleEndian(numChannels, to: &data)
        appendLittleEndian(sampleRate, to: &data)
        appendLittleEndian(byteRate, to: &data)
        appendLittleEndian(blockAlign, to: &data)
        appendLittleEndian(bitsPerSample, to: &data)
        data.append(contentsOf: "data".utf8)
        appendLittleEndian(dataSize, to: &data)
        data.append(pcmBytes)
        return data
    }

    private static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }
}
