// SPDX-License-Identifier: MIT
import AppIntents
import Foundation
import PestoCore

/// A collection the widget may be set to show (ADR 0060). The picker lists only what the sealed snapshot carries: the
/// extension never opens the store.
struct WidgetCollectionEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Collection"
    static let defaultQuery = WidgetCollectionQuery()

    let id: UUID
    let name: String
    let symbolName: String

    init(id: UUID, name: String, symbolName: String) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
    }

    init(_ collection: WidgetCollection) {
        self.init(id: collection.id, name: collection.name, symbolName: collection.symbolName)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: DisplayRepresentation.Image(systemName: symbolName))
    }
}

struct WidgetCollectionQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [WidgetCollectionEntity] {
        let carried = Self.carried()
        return identifiers.compactMap { id in carried.first { $0.id == id } }
    }

    func suggestedEntities() async throws -> [WidgetCollectionEntity] {
        Self.carried()
    }

    private static func carried() -> [WidgetCollectionEntity] {
        (WidgetSnapshotReader.read()?.collections ?? []).map(WidgetCollectionEntity.init)
    }
}
