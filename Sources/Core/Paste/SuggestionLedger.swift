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
        var declinedOn: Date?
        var declines = 0
    }

    static let backOffDays = 30
    static let declinesBeforeFinal = 2

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
            var declinedOn: Date?
            var declines = 0
            if parts.count >= 4, !parts[3].isEmpty {
                let outcomeStr = parts[3]
                if outcomeStr == "accepted" {
                    outcome = .accepted
                } else if outcomeStr.starts(with: "declined") {
                    let pasteCount = parts.count >= 5 ? Int(parts[4]) ?? 0 : 0
                    outcome = .declined(atPasteCount: pasteCount)
                    if parts.count >= 6, let seconds = TimeInterval(parts[5]) {
                        declinedOn = Date(timeIntervalSince1970: seconds)
                    }
                    declines = parts.count >= 7 ? Int(parts[6]) ?? 1 : 1
                } else if outcomeStr == "acknowledged" {
                    outcome = .acknowledged
                } else if outcomeStr == "keep" {
                    outcome = .keep
                }
            }
            parsed.append(Entry(
                kind: kind, clipID: clipID, shows: shows, outcome: outcome, declinedOn: declinedOn, declines: declines
            ))
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
                let seconds = Int(entry.declinedOn?.timeIntervalSince1970 ?? 0)
                extra = "|\(count)|\(seconds)|\(entry.declines)"
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

    public var clipIDs: Set<UUID> {
        Set(entries.map(\.clipID))
    }

    public func shows(_ kind: ShelfSuggestionKind, _ clip: UUID) -> Int {
        entries.last(where: { $0.kind == kind && $0.clipID == clip })?.shows ?? 0
    }

    public func isBlocked(_ kind: ShelfSuggestionKind, _ clip: UUID, pastes: Int, now: Date) -> Bool {
        guard let entry = entries.last(where: { $0.kind == kind && $0.clipID == clip }),
              let outcome = entry.outcome else { return false }
        guard case let .declined(declinedAt) = outcome else { return true }
        if entry.declines >= SuggestionLedger.declinesBeforeFinal { return true }
        guard let declinedOn = entry.declinedOn else { return pastes < declinedAt * 2 }
        let backOff = TimeInterval(SuggestionLedger.backOffDays) * 86_400
        return pastes < declinedAt * 2 || now < declinedOn.addingTimeInterval(backOff)
    }

    public mutating func noteShown(_ kind: ShelfSuggestionKind, _ clip: UUID, pastes: Int, now: Date) {
        if let idx = entries.lastIndex(where: { $0.kind == kind && $0.clipID == clip }) {
            entries[idx].shows += 1
            if entries[idx].outcome == nil,
               entries[idx].shows >= ShelfSuggestionPolicy.Thresholds.ignoredShowsBeforeMute
            {
                entries[idx].outcome = .declined(atPasteCount: pastes)
                entries[idx].declinedOn = now
                entries[idx].declines = 1
            }
        } else {
            entries.append(Entry(kind: kind, clipID: clip, shows: 1, outcome: nil))
        }
        trim()
    }

    public mutating func resolve(_ kind: ShelfSuggestionKind, _ clip: UUID, as outcome: Outcome, now: Date = Date()) {
        var declinedOn: Date?
        if case .declined = outcome { declinedOn = now }
        if let idx = entries.lastIndex(where: { $0.kind == kind && $0.clipID == clip }) {
            entries[idx].outcome = outcome
            entries[idx].declinedOn = declinedOn
            entries[idx].declines = declinedOn == nil ? 0 : entries[idx].declines + 1
        } else {
            entries.append(Entry(
                kind: kind, clipID: clip, shows: 1, outcome: outcome,
                declinedOn: declinedOn, declines: declinedOn == nil ? 0 : 1
            ))
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
