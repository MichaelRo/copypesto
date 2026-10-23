// SPDX-License-Identifier: MIT
import Foundation

/// Multi-selection keyed by item identity. Positions shift whenever a new clip lands or a filter
/// changes, so an index-based selection acted on the wrong items.
public struct GridSelection: Equatable, Sendable {
    private var ids: Set<UUID> = []

    public init() {}

    public var count: Int {
        ids.count
    }

    public var isEmpty: Bool {
        ids.isEmpty
    }

    public func contains(_ id: UUID) -> Bool {
        ids.contains(id)
    }

    public mutating func toggle(_ id: UUID) {
        if !ids.insert(id).inserted { ids.remove(id) }
    }

    public mutating func selectAll(_ visible: [UUID]) {
        ids = Set(visible)
    }

    public mutating func clear() {
        ids.removeAll()
    }

    public mutating func prune(keeping visible: [UUID]) {
        ids.formIntersection(visible)
    }

    public func ordered(in visible: [UUID]) -> [UUID] {
        visible.filter { ids.contains($0) }
    }
}
