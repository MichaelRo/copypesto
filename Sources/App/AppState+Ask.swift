// SPDX-License-Identifier: MIT
import PestoCore

extension AppState {
    func apply(_ query: AskPestoQuery) {
        searchText = query.keywords
        lastAsk = query
        searchTypeFilter = Set(query.types.map(\.rawValue))
        searchDateFilter = query.range
        isSearchActive = true
        Announcer.announce(query.hasFilters || !query.keywords.isEmpty
            ? "Filters applied: \(query.summary)"
            : "No filters found in that. Showing everything.")
    }

    /// Cancels any in-flight Ask Pesto interpretation and prevents stale results from applying.
    func cancelAsk() {
        askGeneration &+= 1
        askTask?.cancel()
        askTask = nil
        if isAsking { isAsking = false }
    }

    var offersAsk: Bool {
        let stillApplied = lastAsk.map {
            Set($0.types.map(\.rawValue)) == searchTypeFilter && $0.range == searchDateFilter
        } ?? false
        return AskHeuristic.offersAsk(text: searchText, lastAppliedKeywords: stillApplied ? lastAsk?.keywords : nil)
    }

    /// Turns the search text into filters (the Ask button, ⌘Return, and Return when a sentence finds nothing).
    func askPesto() async {
        await askPesto(using: Self.askInterpreter())
    }

    func askPesto(using interpreter: FallbackQueryInterpreter) async {
        cancelAsk()
        let generation = askGeneration
        let rawQuery = searchText
        let task = Task<Void, Never> { [weak self] in
            let query = await interpreter.interpret(rawQuery)
            guard let self, !Task.isCancelled, self.askGeneration == generation, !self.isHistoryLocked else { return }
            self.apply(query)
        }
        askTask = task
        isAsking = true
        await task.value
        if askGeneration == generation {
            askTask = nil
            isAsking = false
        }
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
