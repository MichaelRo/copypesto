// SPDX-License-Identifier: MIT
import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

public enum AIAvailability: Sendable, Equatable {
    public enum Reason: Sendable, CaseIterable {
        case needsNewerMacOS, deviceNotEligible, notEnabled, modelNotReady, turnedOff, unknown
    }

    case available
    case unavailable(Reason)

    public var isAvailable: Bool {
        self == .available
    }

    /// How AI controls are drawn (ADR 0005). Never possible on this Mac: hidden. The person can fix it, or turned it
    /// off
    /// in Pesto: disabled, with the reason.
    public enum Presentation: Equatable, Sendable {
        case enabled
        case hidden
        case disabled(String)
    }

    public var presentation: Presentation {
        guard case let .unavailable(reason) = self else { return .enabled }
        return switch reason {
        case .needsNewerMacOS, .deviceNotEligible: .hidden
        case .notEnabled, .modelNotReady, .turnedOff, .unknown: .disabled(message)
        }
    }

    /// True when the fix is a switch in System Settings, so a button to open it helps.
    public var canBeFixedInSystemSettings: Bool {
        self == .unavailable(.notEnabled)
    }

    public var message: String {
        guard case let .unavailable(reason) = self else { return "" }
        return switch reason {
        case .needsNewerMacOS:
            "AI actions need macOS 26 or later."
        case .deviceNotEligible:
            "AI actions need a Mac with Apple Intelligence (Apple silicon)."
        case .notEnabled:
            "Turn on Apple Intelligence in System Settings to use AI actions."
        case .modelNotReady:
            "Apple Intelligence is still getting ready. Try again in a few minutes."
        case .turnedOff:
            "Turned off in Pesto\u{2019}s settings."
        case .unknown:
            "AI actions are not available on this Mac right now."
        }
    }

    /// The person's own switch in Settings (General), on unless they turned it off. Every on-device AI feature asks
    /// this first, so one switch covers actions, Describe Image, picture screening and Ask Pesto.
    public static let enabledDefaultsKey = Setting.appleIntelligenceEnabled.name

    public static func isUserEnabled(defaults: UserDefaults = AppDefaults.store) -> Bool {
        defaults.object(forKey: enabledDefaultsKey) == nil || defaults.bool(forKey: enabledDefaultsKey)
    }

    public static var current: AIAvailability {
        current(defaults: AppDefaults.store)
    }

    public static func current(defaults: UserDefaults) -> AIAvailability {
        isUserEnabled(defaults: defaults) ? system : .unavailable(.turnedOff)
    }

    /// What the Mac itself reports, ignoring the person's switch.
    public static var system: AIAvailability {
        if RuntimeConfiguration.current.mode == .uiTest, RuntimeConfiguration.current.aiFixture { return .available }
        #if canImport(FoundationModels)
            guard #available(macOS 26, *) else { return .unavailable(.needsNewerMacOS) }
            switch SystemLanguageModel.default.availability {
            case .available: return .available
            case let .unavailable(reason):
                switch reason {
                case .deviceNotEligible: return .unavailable(.deviceNotEligible)
                case .appleIntelligenceNotEnabled: return .unavailable(.notEnabled)
                case .modelNotReady: return .unavailable(.modelNotReady)
                @unknown default: return .unavailable(.unknown)
                }
            }
        #else
            return .unavailable(.needsNewerMacOS)
        #endif
    }
}

public extension AIAction {
    func isEnabled(availability: AIAvailability, supportsVision: Bool) -> Bool {
        guard availability.isAvailable else { return false }
        return self == .describeImage ? supportsVision : true
    }
}
