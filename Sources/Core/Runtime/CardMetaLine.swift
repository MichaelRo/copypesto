// SPDX-License-Identifier: MIT
import Foundation

/// The one line of facts at the foot of a card, which took the place of the header band (ADR 0044): what the line may
/// say, from the fullest wording to the shortest, so the view shows the first that fits. At rest it is the app's name
/// and the age; the clip's size joins on the card that is focused or pointed at; a title the person gave takes the
/// app's place and is the last thing given up.
public enum CardMetaLine {
    public struct Facts: Equatable, Sendable {
        public var title: String?
        public var source: String?
        public var age: String
        /// The clip's size in words, fullest first ("149 characters · 5 lines", "149 characters").
        public var measure: [String]
        /// A card that shows all of a short text has nothing to measure for the reader.
        public var showsWholeClip: Bool
        public var isActive: Bool

        public init(
            title: String? = nil,
            source: String? = nil,
            age: String,
            measure: [String] = [],
            showsWholeClip: Bool = false,
            isActive: Bool = false
        ) {
            self.title = title
            self.source = source
            self.age = age
            self.measure = measure
            self.showsWholeClip = showsWholeClip
            self.isActive = isActive
        }
    }

    public static let separator = " \u{00B7} "

    public static func candidates(_ facts: Facts) -> [String] {
        let lead = facts.title ?? facts.source
        let measures = facts.isActive && !facts.showsWholeClip ? facts.measure : []
        var lines = measures.map { join([lead, facts.age, $0]) }
        lines.append(join([lead, facts.age]))
        lines.append(facts.title ?? facts.age)
        var seen: Set<String> = []
        return lines.filter { seen.insert($0).inserted }
    }

    /// A snippet's braces and a ⌃ shortcut are only ever on a pinned clip, so the pin beside either says nothing new.
    public static func showsPin(isPinned: Bool, isSnippet: Bool, hasShortcut: Bool) -> Bool {
        isPinned && !isSnippet && !hasShortcut
    }

    private static func join(_ parts: [String?]) -> String {
        parts.compactMap(\.self).filter { !$0.isEmpty }.joined(separator: separator)
    }
}
