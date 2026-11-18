// SPDX-License-Identifier: MIT
import PestoCore

/// The AI actions a clip's menus offer, decided as the Mac's context menu decides them (ADR 0005): none for a secret,
/// a covered, filtered or still-judged clip or a locked history, text actions for text and code, Describe Image for a
/// picture. A model that can never run on this device hides them; one the person can fix, or turned off in Pesto,
/// shows them disabled with the reason.
enum CardAIActions {
    struct Facts: Equatable {
        let type: ClipboardType
        let isSecret: Bool
        let isCovered: Bool
        let isFiltered: Bool
        let isPending: Bool
        let isLocked: Bool
        let availability: AIAvailability
        let supportsVision: Bool
    }

    struct Offer: Equatable {
        var actions: [AIAction] = []
        var isEnabled = false
        /// Why the actions are greyed out; nil when they are enabled.
        var reason: String?

        var isEmpty: Bool {
            actions.isEmpty
        }
    }

    static func offer(for facts: Facts) -> Offer {
        guard !facts.isSecret, !facts.isCovered, !facts.isFiltered, !facts.isPending, !facts.isLocked else {
            return Offer()
        }
        let actions = AIAction.actions(for: facts.type)
        guard !actions.isEmpty else { return Offer() }
        switch facts.availability.presentation {
        case .hidden:
            return Offer()
        case let .disabled(message):
            return Offer(actions: actions, isEnabled: false, reason: message)
        case .enabled:
            if facts.type == .image, !facts.supportsVision {
                return Offer(actions: actions, isEnabled: false, reason: visionReason)
            }
            return Offer(actions: actions, isEnabled: true, reason: nil)
        }
    }

    static var visionReason: String {
        String(
            localized: "Describe Image needs a model that can read pictures, which this device\u{2019}s does not have yet."
        )
    }
}
