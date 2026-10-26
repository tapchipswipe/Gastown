import Foundation

/// Explicitly local history search. External Screenpipe is a separate user action.
public struct EmbeddedScreenpipeClient: ScreenpipeSearching {
    private let storeProvider: @Sendable () async throws -> any HistoryRepository
    public init(store: any HistoryRepository) { storeProvider = { store } }
    public init(storeProvider: @escaping @Sendable () async throws -> any HistoryRepository) { self.storeProvider = storeProvider }
    public func search(_ query: String, token: String = "") async throws -> ScreenpipeResult {
        try Task.checkCancellation()
        let store = try await storeProvider()
        let page = try await store.page(query, after: nil, limit: 30)
        try Task.checkCancellation()
        return ScreenpipeResult(events: page.events, omitted: 0)
    }
}
