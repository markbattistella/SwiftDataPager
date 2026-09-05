//
// Project: SwiftDataPager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import SwiftData
import SwiftUI

/// A property wrapper that provides a paginated, **live** query interface for any
/// `PersistentModel`.
///
/// `PagedQuery` is a thin, ergonomic wrapper around SwiftData's `@Query`: it fetches up to
/// `maxWindow` rows once, then widens the visible prefix as `loadMore()` is called. Results stay
/// live — inserts, edits, and deletes made anywhere against the same `ModelContext` are reflected
/// automatically, with no manual refresh or reset required.
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
///     filterPredicate: #Predicate { $0.name.localizedStandardContains("data") },
///     logger: .default,
///     animation: .default
/// ) private var items: [MyModel]
/// ```
@MainActor
@propertyWrapper
public struct PagedQuery<Model>: @MainActor DynamicProperty where Model: PersistentModel {
    /// The live fetch, capped at `maxWindow`. Its descriptor is fixed for the lifetime of the
    /// wrapper — see `update()` for why it must never be rebuilt after `init`.
    @Query
    private var rawItems: [Model]

    /// How many of `rawItems` are currently exposed through `wrappedValue`. Grows by `pageSize`
    /// each time `loadMore()` is called, up to `maxWindow`.
    @State
    private var window: Int

    /// The number of items to grow the window by each time `loadMore()` is called.
    private let pageSize: Int

    /// The hard ceiling on how many rows this query will ever fetch.
    ///
    /// `Query` exposes no way to widen its `fetchLimit` after construction, and rebuilding the
    /// `Query` value inside `update()` discards its fetched state (SwiftUI only installs
    /// `Query`'s storage on values built during `init`). So the fetch is sized to this ceiling
    /// once, up front, and pagination beyond that point is done client-side via
    /// `rawItems.prefix(window)`. Rows beyond `maxWindow` are invisible to this query.
    private let maxWindow: Int

    /// The sort descriptors to apply during fetching.
    private let sortDescriptors: [SortDescriptor<Model>]

    /// Optional predicate to filter results.
    private let filterPredicate: Predicate<Model>?

    /// Logging utility for pagination events.
    internal let logger: any PaginationLogger

    /// The animation SwiftData applies when rows enter, leave, or move within the fetched
    /// window. `nil` means no animation, matching `@Query`'s own default.
    private let animation: Animation?

    /// The current list of loaded models.
    public var wrappedValue: [Model] { Array(rawItems.prefix(window)) }

    /// A reference to the full `PagedQuery`, exposing control methods.
    public var projectedValue: PagedQuery<Model> { self }

    /// Indicates whether all matching data has been loaded — i.e. the underlying store has no
    /// more rows beyond the current window.
    public var hasReachedEnd: Bool { rawItems.count <= window }

    /// The current pagination phase.
    public var phase: PaginationPhase { hasReachedEnd ? .complete : .idle }
}

// MARK: - Init

extension PagedQuery {
    /// Creates a new `PagedQuery` instance.
    ///
    /// - Parameters:
    ///   - fetchLimit: Number of items to fetch initially, and to grow the window by on each
    ///     `loadMore()` call. Defaults to `10`.
    ///   - maxWindow: The hard ceiling on how many rows will ever be fetched, regardless of how
    ///     many times `loadMore()` is called. Rows beyond this ceiling are invisible to the
    ///     query. Defaults to `500`; raise it if a screen legitimately needs to page further than
    ///     that. Values below `fetchLimit` are clamped up to `fetchLimit`.
    ///   - sortDescriptors: Sorting applied during fetch. Defaults to `empty`.
    ///   - filterPredicate: Optional filter to apply to results. Defaults to `nil`.
    ///   - logger: Logging configuration. Defaults to `.none`.
    ///   - animation: The animation SwiftData applies when rows enter, leave, or move within the
    ///     fetched window. Defaults to `nil` (no animation), matching `@Query`'s own default.
    public init(
        fetchLimit: Int = 10,
        maxWindow: Int = 500,
        sortDescriptors: [SortDescriptor<Model>] = [],
        filterPredicate: Predicate<Model>? = nil,
        logger: PaginationLoggerConfig = .none,
        animation: Animation? = nil
    ) {
        let pageSize = max(1, fetchLimit)
        let resolvedMaxWindow = max(pageSize, maxWindow)
        self.pageSize = pageSize
        self.maxWindow = resolvedMaxWindow
        self.sortDescriptors = sortDescriptors
        self.filterPredicate = filterPredicate
        self.animation = animation
        self._window = State(initialValue: pageSize)

        switch logger {
            case .none:
                self.logger = SilentPaginationLogger()
            case .default:
                self.logger = DefaultPaginationLogger()
            case .custom(let customLogger):
                self.logger = customLogger
        }

        self._rawItems = Self.makeQuery(
            descriptor: Self.descriptor(
                maxWindow: resolvedMaxWindow,
                predicate: filterPredicate,
                sortDescriptors: sortDescriptors
            ),
            animation: animation
        )
    }
}

// MARK: - Public API

extension PagedQuery {
    /// Automatically invoked by SwiftUI when the view's state changes.
    ///
    /// This only forwards to the underlying `Query`'s own `update()` — it must **not** replace
    /// `_rawItems` with a newly-built `Query` value here. SwiftUI installs a `Query`'s storage
    /// (model context, fetched results) via the `DynamicProperty` machinery before `body` runs;
    /// a `Query` constructed inside `update()` never gets that storage installed, so its fetched
    /// results are always empty. `loadMore()`/`reset()` are handled entirely client-side instead
    /// (see `wrappedValue`), which is why the fetch descriptor can stay fixed for the wrapper's
    /// lifetime.
    public mutating func update() {
        _rawItems.update()
    }

    /// Grows the visible window by `fetchLimit`, revealing the next page of already-fetched
    /// results, up to `maxWindow`.
    ///
    /// Because the underlying data is a live `@Query`, this never triggers a network- or
    /// disk-bound wait — it simply widens the prefix of `rawItems` exposed through
    /// `wrappedValue`.
    public func loadMore() {
        guard !hasReachedEnd else {
            logger.log("loadMore skipped — already at end.")
            return
        }
        window = min(window + pageSize, maxWindow)
        logger.log("Window increased to \(window).")
    }

    /// Resets the fetch window back to its initial size.
    ///
    /// Call this when switching to a meaningfully different scope (e.g. a different parent
    /// record) if you want the view to start from a small window again. Correctness does not
    /// depend on calling this — changing `filterPredicate`/`sortDescriptors` always re-executes
    /// the live query against the new arguments — this only affects how large the *first* page
    /// under the new scope is.
    public func reset() {
        window = pageSize
        logger.log("Reset pagination window to \(pageSize).")
    }
}

// MARK: - Fetch descriptor

extension PagedQuery {
    /// Builds the fixed fetch descriptor used for the wrapper's entire lifetime.
    ///
    /// `fetchLimit` is `maxWindow`, not the current window — the descriptor never changes after
    /// `init`, so it's sized to the ceiling once. `hasReachedEnd` is answered by comparing
    /// `rawItems.count` (which is `min(totalMatchingRows, maxWindow)`) against `window`, with no
    /// separate `fetchCount` query needed.
    nonisolated static func descriptor(
        maxWindow: Int,
        predicate: Predicate<Model>?,
        sortDescriptors: [SortDescriptor<Model>]
    ) -> FetchDescriptor<Model> {
        var descriptor = FetchDescriptor<Model>(predicate: predicate, sortBy: sortDescriptors)
        descriptor.fetchLimit = maxWindow
        return descriptor
    }

    /// Builds the underlying `@Query`, applying `animation` only when one was supplied — `Query`
    /// has no initialiser accepting an optional `Animation`, so `nil` must route to the
    /// non-animating overload to preserve `@Query`'s own default behaviour.
    @MainActor
    static func makeQuery(
        descriptor: FetchDescriptor<Model>,
        animation: Animation?
    ) -> Query<Model, [Model]> {
        if let animation {
            Query(descriptor, animation: animation)
        }
        else {
            Query(descriptor)
        }
    }
}
