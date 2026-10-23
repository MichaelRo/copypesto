// SPDX-License-Identifier: MIT
import PestoCore

extension AppState {
    func apply(_ query: AskPestoQuery) {
        searchText = query.keywords
        searchTypeFilter = Set(query.types.map(\.rawValue))
        searchDateFilter = switch query.range {
        case .all: .all
        case .today: .today
        case .yesterday: .yesterday
        case .week: .week
        case .month: .month
        }
        isSearchActive = true
        Announcer.announce(query.hasFilters || !query.keywords.isEmpty
            ? "Filters applied: \(query.summary)"
            : "No filters found in that. Showing everything.")
    }

    /// Turns the search text into filters (the Ask button, ⌘Return, and Return when a sentence finds nothing).
    func askPesto() async {
        let query = await Self.askInterpreter().interpret(searchText)
        apply(query)
    }

    static func askInterpreter() -> FallbackQueryInterpreter {
        (LaunchMode.current.usesSystemIntegrations || RuntimeConfiguration.current.usesRealDevice)
            && OnDeviceQueryInterpreter.isAvailable
            ? FallbackQueryInterpreter(primary: OnDeviceQueryInterpreter())
            : FallbackQueryInterpreter(primary: NoModel())
    }

    private struct NoModel: QueryInterpreting {
        func interpret(_: String) async throws -> AskPestoQuery {
            throw AppleIntelligenceClient.ClientError.unavailable
        }
    }
}

extension AppState {
    /// The recent searches are offered on an empty, focused field, but never on top of filters that Ask or a chip has
    /// already set.
    func offersRecentSearches(_ isFocused: Bool, history: [String]) -> Bool {
        isFocused && searchText.isEmpty && !history.isEmpty && searchTypeFilter.isEmpty && searchDateFilter == .all
            && !searchSensitiveOnly && !searchRemoteOnly
    }
}
