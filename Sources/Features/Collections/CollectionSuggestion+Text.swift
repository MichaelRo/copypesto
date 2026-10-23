// SPDX-License-Identifier: MIT
import PestoCore

extension CollectionSuggestion.Group {
    var title: String {
        switch self {
        case .fromYourClips: String(localized: "From your clips")
        case .topics: String(localized: "Topics")
        case .starters: String(localized: "Starters")
        }
    }

    var caption: String {
        switch self {
        case .fromYourClips:
            String(
                localized: "Smart collections that fill themselves from what you copy. No clip moves."
            )
        case .topics:
            String(
                localized: "Clips about the same thing, found on this Mac. Each fills itself from a word they share."
            )
        case .starters:
            String(localized: "There is not enough history to learn from yet, so here are a few to begin with.")
        }
    }
}
