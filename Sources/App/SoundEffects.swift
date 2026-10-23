// SPDX-License-Identifier: MIT
import AppKit
import PestoCore

@MainActor
enum SoundEffects {
    enum Kind {
        case copy
        case paste
    }

    private static var soundCache: [String: (copy: NSSound, paste: NSSound)] = [:]

    private static func sounds(for theme: AppTheme) -> (copy: NSSound, paste: NSSound)? {
        if let cached = soundCache[theme.rawValue] { return cached }
        guard let copy = NSSound(data: SoundEffectPolicy.wavData(for: .copy, theme: theme)),
              let paste = NSSound(data: SoundEffectPolicy.wavData(for: .paste, theme: theme)) else
        {
            return nil
        }
        let pair = (copy: copy, paste: paste)
        soundCache[theme.rawValue] = pair
        return pair
    }

    static func play(_ kind: Kind) {
        guard SoundEffectPolicy.shouldPlay(
            enabled: AppDefaults.store.value(for: Setting.soundEffects),
            systemIntegrations: LaunchMode.current.usesSystemIntegrations
        ) else { return }
        let theme = AppTheme(stored: AppDefaults.store.value(for: Setting.appTheme))
        guard let pair = sounds(for: theme) else { return }
        let base = kind == .copy ? pair.copy : pair.paste
        (base.copy() as? NSSound)?.play()
    }
}
