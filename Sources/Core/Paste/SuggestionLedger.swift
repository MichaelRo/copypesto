// SPDX-License-Identifier: MIT
import Foundation

public struct SuggestionLedger: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case accepted
        case declined(atPasteCount: Int)
        case acknowledged
        case keep
    }

    private struct Entry: Equatable {
        var kind: ShelfSuggestionKind
        var clipID: UUID
        var shows: Int
        var outcome: Outcome?
    }

    private var entries: [Entry]

    public init(serialized: String) {
        var parsed: [Entry] = []
        for line in serialized.split(separator: "\n") {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 3,
                  let kind = ShelfSuggestionKind(rawValue: parts[0]),
                  let clipID = UUID(uuidString: parts[1]),
                  let shows = Int(parts[2]) else { continue }

            var outcome: Outcome?
            if parts.count >= 4, !parts[3].isEmpty {
                let outcomeStr = parts[3]
                if outcomeStr == "accepted" {
                    outcome = .accepted
                } else if outcomeStr.starts(with: "declined") {
                    let pasteCount = parts.count >= 5 ? Int(parts[4]) ?? 0 : 0
                    outcome = .declined(atPasteCount: pasteCount)
                } else if outcomeStr == "acknowledged" {
                    outcome = .acknowledged
                } else if outcomeStr == "keep" {
                    outcome = .keep
                }
            }
            parsed.append(Entry(kind: kind, clipID: clipID, shows: shows, outcome: outcome))
        }
        self.entries = parsed
    }

    public var serialized: String {
        entries.map { entry in
            let outcomeStr: String
            let extra: String
            switch entry.outcome {
            case .accepted:
                outcomeStr = "accepted"
                extra = ""
            case let .declined(count):
                outcomeStr = "declined"
                extra = "|\(count)"
            case .acknowledged:
                outcomeStr = "acknowledged"
                extra = ""
            case .keep:
                outcomeStr = "keep"
                extra = ""
            case nil:
                outcomeStr = ""
                extra = ""
            }
            return "\(entry.kind.rawValue)|\(entry.clipID.uuidString)|\(entry.shows)|\(outcomeStr)\(extra)"
        }.joined(separator: "\n")
    }

    public func shows(_ kind: ShelfSuggestionKind, _ clip: UUID) -> Int {
        entries.last(where: { $0.kind == kind && $0.clipID == clip })?.shows ?? 0
    }

    public func isSilenced(_ clip: UUID, currentPastes: Int? = nil) -> Bool {
        for entry in entries where entry.clipID == clip {
            if entry.shows >= 3, entry.outcome == nil {
                return true
            }
            if case let .declined(declinedCount) = entry.outcome {
                if let currentPastes, currentPastes >= declinedCount * 2, currentPastes > 0 {
                    continue
                }
                return true
            }
        }
        return false
    }

    public func isResolved(_ kind: ShelfSuggestionKind, _ clip: UUID) -> Bool {
        entries.contains(where: { $0.kind == kind && $0.clipID == clip && $0.outcome != nil })
    }

    public mutating func noteShown(_ kind: ShelfSuggestionKind, _ clip: UUID) {
        if let idx = entries.lastIndex(where: { $0.kind == kind && $0.clipID == clip }) {
            entries[idx].shows += 1
        } else {
            entries.append(Entry(kind: kind, clipID: clip, shows: 1, outcome: nil))
        }
        trim()
    }

    public mutating func resolve(_ kind: ShelfSuggestionKind, _ clip: UUID, as outcome: Outcome) {
        if let idx = entries.lastIndex(where: { $0.kind == kind && $0.clipID == clip }) {
            entries[idx].outcome = outcome
        } else {
            entries.append(Entry(kind: kind, clipID: clip, shows: 1, outcome: outcome))
        }
        trim()
    }

    public mutating func clear() {
        entries.removeAll()
    }

    public mutating func prune(existingClipIDs: Set<UUID>) {
        entries.removeAll(where: { !existingClipIDs.contains($0.clipID) })
    }

    private mutating func trim() {
        if entries.count > 200 {
            entries.removeFirst(entries.count - 200)
        }
    }
}
