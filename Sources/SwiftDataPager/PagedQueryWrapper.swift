//
// Project: SwiftDataPager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import SwiftUI
import SwiftData

/// A property wrapper that provides a paginated query interface for any `PersistentModel`.
///
/// `PagedQuery` handles incremental data loading, maintains pagination state, and tracks
/// fetch errors or completion. Ideal for use in SwiftUI views where on-demand loading is needed.
///
/// ### Basic usage:
/// ```swift
/// @PagedQuery(fetchLimit: 20) var results: [MyModel]
/// ```
///
/// ### Advanced usage with filtering and sorting:
/// ```swift
/// @PagedQuery(
///     fetchLimit: 20,
///     sortDescriptors: [.init(\MyModel.name)],
///     filterPredicate: #Predicate { $0.name.contains("data") },
///     logger: .default
/// ) private var items: [MyModel]
/// ```
@MainActor
@propertyWrapper
public struct PagedQuery<Model>: DynamicProperty where Model: PersistentModel {
    
    /// Access to the SwiftData model context used for fetching.
    @Environment(\.modelContext) private var modelContext
    
    /// The list of items fetched so far.
    @State private var items: [Model] = []
    
    /// Keeps track of the current fetch offset (i.e. how many items have been fetched so far).
    @State private var fetchOffset: Int = 0
    
    /// Tracks the current state of pagination: idle, fetching, all loaded, or error.
    @State private(set) var state: PaginationState = .idle
    
    /// The current list of loaded models.
    public var wrappedValue: [Model] { items }
    
    /// A reference to the full `PagedQuery`, exposing control methods.
    public var projectedValue: PagedQuery<Model> { self }
    
    /// Indicates whether a fetch operation is currently in progress.
    public var isFetching: Bool { state.isFetching }
    
    /// Indicates whether all data has been loaded.
    public var hasReachedEnd: Bool { state.isAllLoaded }
    
    /// Returns the most recent error encountered during a fetch, if any.
    public var error: Error? {
        if case .error(let error) = state { return error }
        return nil
    }
    
    /// The number of items to fetch per page.
    private let fetchLimit: Int
    
    /// The sort descriptors to apply during fetching.
    private let sortDescriptors: [SortDescriptor<Model>]
    
    /// Optional predicate to filter results.
    private let filterPredicate: Predicate<Model>?
    
    /// Logging utility for pagination events.
    internal let logger: PaginationLogger
}

// MARK: - Pagination State

extension PagedQuery {
    
    /// Internal enum tracking the pagination lifecycle.
    internal enum PaginationState {
        
        /// No fetch in progress. Ready to load.
        case idle
        
        /// A fetch is currently in progress.
        case fetching
        
        /// All matching items have been fetched; no more pages left.
        case allLoaded
        
        /// An error occurred during the last fetch attempt.
        ///
        /// - Parameter Error: The error returned from the fetch operation.
        case error(Error)
        
        /// Returns true if no fetch is in progress and more data may be available.
        var isIdle: Bool {
            if case .idle = self { return true }
            return false
        }
        
        /// Returns true if a fetch operation is actively in progress.
        var isFetching: Bool {
            if case .fetching = self { return true }
            return false
        }
        
        /// Returns true if all pages have been fetched.
        var isAllLoaded: Bool {
            if case .allLoaded = self { return true }
            return false
        }
        
        /// Returns true if the state is currently an error.
        var isError: Bool {
            if case .error = self { return true }
            return false
        }
    }
}

// MARK: - Init

extension PagedQuery {
    
    /// Creates a new `PagedQuery` instance.
    ///
    /// - Parameters:
    ///   - fetchLimit: Number of items to fetch per page. Defaults to `10`.
    ///   - sortDescriptors: Sorting applied during fetch. Defaults to `empty`.
    ///   - filterPredicate: Optional filter to apply to results. Defaults to `nil`.
    ///   - logger: Logging configuration. Defaults to `.none`.
    public init(
        fetchLimit: Int = 10,
        sortDescriptors: [SortDescriptor<Model>] = [],
        filterPredicate: Predicate<Model>? = nil,
        logger: PaginationLoggerConfig = .none
    ) {
        self.fetchLimit = fetchLimit
        self.sortDescriptors = sortDescriptors
        self.filterPredicate = filterPredicate
        
        switch logger {
            case .none:
                self.logger = SilentPaginationLogger()
            case .default:
                self.logger = DefaultPaginationLogger()
            case .custom(let customLogger):
                self.logger = customLogger
        }
    }
}

// MARK: - Public API

extension PagedQuery {

    /// Automatically invoked by SwiftUI when the view’s state changes.
    ///
    /// This method is required by `DynamicProperty` and is called by the SwiftUI runtime.
    /// Because SwiftUI may call this method from a background thread, it is marked `nonisolated`
    /// and safely dispatches any main-thread work.
    ///
    /// You generally don’t need to call this directly. Instead, rely on SwiftUI to trigger it
    /// when your property wrapper is used in a view.
    ///
    /// If the internal pagination state indicates no items have been loaded yet and a fetch is allowed,
    /// it triggers an initial call to `loadMore()`.
    nonisolated public func update() {
        // Dispatch the safe part to the main actor
        Task { @MainActor in
            self._performAutoLoadIfNeeded()
        }
    }

    /// Loads the next page of results if appropriate.
    public func loadMore() {
        
        // Don't fetch if we've already reached the end of the available data.
        if hasReachedEnd {
            logger.log("Fetch skipped — already at end.")
            return
        }
        
        // Avoid triggering multiple concurrent fetches.
        guard !isFetching else {
            logger.log("Fetch skipped - already fetching.")
            return
        }
        
        // Skip if currently in error state. Use `retry()` to attempt again.
        guard !state.isError else {
            logger.log("Fetch skipped - currently in error state. Use retry().")
            return
        }
        
        logger.log("Initiating fetch task for offset: \(fetchOffset)")
        
        // Kick off the asynchronous fetch for the next page.
        Task { @MainActor in
            await fetchPage(startingAt: fetchOffset)
        }
    }
    
    /// Resets pagination and triggers a fresh initial load.
    public func reset() {
        items = []
        fetchOffset = 0
        state = .idle
        logger.log("Reset pagination state. Triggering initial load.")
        loadMore()
    }
    
    /// Retries a failed fetch operation if currently in an error state.
    public func retry() {
        if case .error = state {
            logger.log("Retry triggered.")
            state = .idle
            loadMore()
        } else {
            logger.log("Retry called but not in an error state.")
        }
    }
}

// MARK: - Private API

extension PagedQuery {

    /// Performs an initial paginated fetch if no items have been loaded yet.
    ///
    /// This method is dispatched from the nonisolated `update()` method and safely runs
    /// on the main actor. It checks if the current pagination state is idle and no data
    /// has been loaded yet, and if so, triggers a `loadMore()` call to begin fetching.
    ///
    /// This ensures that paginated queries start automatically when a view appears
    /// and SwiftUI triggers its lifecycle updates.
    private func _performAutoLoadIfNeeded() {
        if fetchOffset == 0 && items.isEmpty && state.isIdle {
            logger.log("PagedQuery.update: triggering initial loadMore()")
            loadMore()
        }
    }

    /// Asynchronously fetches a page of data starting at a given offset.
    ///
    /// - Parameter offset: The offset from which to begin fetching items.
    @MainActor
    private func fetchPage(startingAt offset: Int) async {
        
        // Prevent duplicate or unnecessary fetches due to race conditions or state drift.
        guard !state.isFetching, !state.isAllLoaded, !state.isError else {
            logger.log("""
            Fetch task started but state changed before execution
             - isFetching: \(state.isFetching)
             - isAllLoaded: \(state.isAllLoaded)
             - isError: \(state.isError)
            Aborting fetch.
            """)
            return
        }
        
        state = .fetching
        logger.log("Fetching page starting at offset: \(offset), limit: \(fetchLimit)")
        
        do {
            
            // Build the descriptor that defines how we fetch our next page of items.
            var descriptor = FetchDescriptor<Model>(
                predicate: filterPredicate,
                sortBy: sortDescriptors
            )
            
            // Separate descriptor to count the total number of matching items.
            let countDescriptor = FetchDescriptor<Model>(predicate: filterPredicate)
            
            // Get the total number of items that match our filter.
            let totalItemCount = try modelContext.fetchCount(countDescriptor)
            
            let safeOffset = min(min(totalItemCount, offset), items.count)
            
            descriptor.fetchLimit = fetchLimit
            descriptor.fetchOffset = safeOffset
            
            // Fetch the next page of data using the descriptor.
            let newItems = try modelContext.fetch(descriptor)
            
            // Append the newly fetched items to the list.
            items.append(contentsOf: newItems)
            
            // Move the offset forward by however many items we just fetched.
            fetchOffset += newItems.count
            
            // Log useful debug info — great for tracking fetch behaviour over time.
            logger.log("""
            Page fetched:
             - Fetched this round: \(newItems.count)
             - Fetched total: \(items.count)
             - Available total (matching predicate): \(totalItemCount)
             - Offset now: \(fetchOffset)
            """)
            
            // Decide what state to enter based on how many items we’ve got.
            if items.count >= totalItemCount {
                
                state = .allLoaded
                logger.log("All items loaded.")
                
            } else if newItems.isEmpty && items.count > 0 {
                
                // Edge case: no new results, but we’ve already got some — assume we’re done.
                state = .allLoaded
                logger.log("Fetched 0 new items, assuming end of list.")
                
            } else {
                
                // More items may still be available, back to idle.
                state = .idle
            }
            
        } catch {
            
            // Any error fetching count or page gets logged and bumps us to error state.
            logger.error("Fetch error: \(error.localizedDescription)")
            state = .error(error)
        }
    }
}
