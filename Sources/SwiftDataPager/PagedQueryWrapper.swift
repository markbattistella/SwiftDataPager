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
/// `PagedQuery` is a thin, ergonomic wrapper around SwiftData's `@Query`: internally it grows
/// the fetched window as `loadMore()` is called, so results stay live — inserts, edits, and
/// deletes made anywhere against the same `ModelContext` are reflected automatically, with no
/// manual refresh or reset required.
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
///     logger: .default
/// ) private var items: [MyModel]
/// ```
@MainActor
@propertyWrapper
public struct PagedQuery<Model>: @MainActor DynamicProperty where Model: PersistentModel {

  /// The live, window-limited fetch. Grows by `pageSize` each time `loadMore()` is called.
  ///
  /// The descriptor's `fetchLimit` is always `window + 1`: the extra row is never exposed
  /// through `wrappedValue`, but its presence is how `hasReachedEnd` is answered without an
  /// extra count query.
  @Query private var rawItems: [Model]

  /// How many items are currently within the fetch window (excludes the one-row peek used to
  /// detect the end of the data).
  @State private var window: Int

  /// The number of items to grow the window by each time `loadMore()` is called.
  private let pageSize: Int

  /// The sort descriptors to apply during fetching.
  private let sortDescriptors: [SortDescriptor<Model>]

  /// Optional predicate to filter results.
  private let filterPredicate: Predicate<Model>?

  /// Logging utility for pagination events.
  internal let logger: any PaginationLogger

  /// The current list of loaded models.
  public var wrappedValue: [Model] { Array(rawItems.prefix(window)) }

  /// A reference to the full `PagedQuery`, exposing control methods.
  public var projectedValue: PagedQuery<Model> { self }

  /// Indicates whether all matching data has been loaded — i.e. the underlying store has no
  /// more rows beyond the current window.
  public var hasReachedEnd: Bool { rawItems.count <= window }

  /// The current pagination phase.
  public var phase: Phase { hasReachedEnd ? .complete : .idle }
}

// MARK: - Init

extension PagedQuery {

  /// Creates a new `PagedQuery` instance.
  ///
  /// - Parameters:
  ///   - fetchLimit: Number of items to fetch initially, and to grow the window by on each
  ///     `loadMore()` call. Defaults to `10`.
  ///   - sortDescriptors: Sorting applied during fetch. Defaults to `empty`.
  ///   - filterPredicate: Optional filter to apply to results. Defaults to `nil`.
  ///   - logger: Logging configuration. Defaults to `.none`.
  public init(
    fetchLimit: Int = 10,
    sortDescriptors: [SortDescriptor<Model>] = [],
    filterPredicate: Predicate<Model>? = nil,
    logger: PaginationLoggerConfig = .none
  ) {
    let pageSize = max(1, fetchLimit)
    self.pageSize = pageSize
    self.sortDescriptors = sortDescriptors
    self.filterPredicate = filterPredicate
    self._window = State(initialValue: pageSize)

    switch logger {
    case .none:
      self.logger = SilentPaginationLogger()
    case .default:
      self.logger = DefaultPaginationLogger()
    case .custom(let customLogger):
      self.logger = customLogger
    }

    self._rawItems = Query(Self.descriptor(
      window: pageSize,
      predicate: filterPredicate,
      sortDescriptors: sortDescriptors
    ))
  }
}

// MARK: - Public API

extension PagedQuery {

  /// Automatically invoked by SwiftUI when the view's state changes.
  ///
  /// This rebuilds the underlying `@Query`'s fetch descriptor from the current window size on
  /// every call, so the live query always reflects the latest `loadMore()`/`reset()` state —
  /// this can't be done inside `init()` alone, since `init()` re-runs on every unrelated
  /// re-render without visibility into `window`'s current, persisted value.
  public mutating func update() {
    _rawItems.update()
    _rawItems = Query(Self.descriptor(
      window: window,
      predicate: filterPredicate,
      sortDescriptors: sortDescriptors
    ))
  }

  /// Grows the fetch window by `fetchLimit`, revealing the next page of already-live results.
  ///
  /// Because the underlying data is a live `@Query`, this never triggers a network- or
  /// disk-bound wait — it simply widens the window SwiftData is already observing.
  public func loadMore() {
    guard !hasReachedEnd else {
      logger.log("loadMore skipped — already at end.")
      return
    }
    window += pageSize
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

  nonisolated static func descriptor(
    window: Int,
    predicate: Predicate<Model>?,
    sortDescriptors: [SortDescriptor<Model>]
  ) -> FetchDescriptor<Model> {
    var descriptor = FetchDescriptor<Model>(predicate: predicate, sortBy: sortDescriptors)
    // Fetch one extra row beyond the window so `hasReachedEnd` can be answered without a
    // separate `fetchCount` query.
    descriptor.fetchLimit = window + 1
    return descriptor
  }
}
