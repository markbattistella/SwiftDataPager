<!-- markdownlint-disable MD024 MD033 MD041 -->
<div align="center">

# SwiftDataPager

<small>Effortless, Live Pagination for SwiftData</small>

![Swift Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmarkbattistella%2FSwiftDataPager%2Fbadge%3Ftype%3Dswift-versions)

![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmarkbattistella%2FSwiftDataPager%2Fbadge%3Ftype%3Dplatforms)

![Licence](https://img.shields.io/badge/Licence-MIT-white?labelColor=blue&style=flat)

</div>

`SwiftDataPager` is a Swift package for incremental, infinite-scroll-style pagination over SwiftData, built as a thin wrapper around `@Query`.

Results are **live**: `SwiftDataPager` grows the size of an underlying `@Query` as you scroll, rather than fetching a static snapshot. Inserts, edits, and deletes made anywhere against the same `ModelContext` — including from a different screen, a background import, or a synced change from another device — show up automatically, with no manual refresh required.

By providing a property wrapper and a handful of view modifiers, `SwiftDataPager` makes infinite scrolling straightforward in SwiftUI, while leaving the actual liveness, diffing, and animation to SwiftData itself.

## Features

- Property-wrapper based pagination, backed by a live `@Query`.
- Optional sort descriptors and predicates.
- Infinite-scroll view modifiers for last-item, threshold, and custom triggers.
- A simple `phase`/`hasReachedEnd` surface for end-of-results state.
- Optional SimpleLogger-backed logging or custom logger integration.

> [!NOTE]
> `SwiftDataPager` is a convenience wrapper around a growing `@Query` window — `@Query` already does the hard part (live observation, diffing, animation). This package's job is just to make the growing-window pattern reusable instead of hand-rolling it per screen.

## Installation

Add `SwiftDataPager` to your Swift project using Swift Package Manager.

```swift
dependencies: [
  .package(url: "https://github.com/markbattistella/SwiftDataPager", from: "26.9.5")
]
```

## Requirements

- Swift 6.2+ (Xcode 26+)
- iOS 17.0+
- macOS 14.0+
- Mac Catalyst 17.0+
- tvOS 17.0+
- watchOS 10.0+
- visionOS 1.0+

## Usage

### Simple

```swift
@PagedQuery(fetchLimit: 20) var movies: [Movie]
```

### Advanced

```swift
@PagedQuery(
  fetchLimit: 10,
  sortDescriptors: [SortDescriptor(\Movie.releaseDate, order: .reverse)],
  filterPredicate: #Predicate { $0.genre == "Action" },
  logger: .default,
  animation: .default
) var actionMovies: [Movie]
```

`fetchLimit` is both the size of the first page and how much the window grows by on each `loadMore()` call.

`animation` controls the animation SwiftData applies when rows enter, leave, or move within the fetched window — it's passed straight through to the underlying `@Query`. It defaults to `nil` (no animation), matching `@Query`'s own default, so existing call sites are unaffected.

## View Modifiers

`SwiftDataPager` comes with several view modifiers to make pagination even easier:

### Automatic Loading on Last Item

```swift
ForEach(movies) { movie in
    MovieRow(movie: movie)
        .onLoadMore(item: movie, in: $movies)
}
```

`.onLoadMore(item:, in:)` works with any `PersistentModel` — there's no `Equatable` conformance to add. Position is tracked by `persistentModelID`.

### Sentinel Loading

`.onLoadMore(item:in:)` attaches one `.task` per row. If you'd rather run a single task for the whole list, place a trailing sentinel view after your `ForEach` instead:

```swift
ForEach(movies) { movie in
    MovieRow(movie: movie)
}
Color.clear
    .frame(height: 1)
    .paginationSentinel(in: $movies)
```

This calls `loadMore()` whenever the sentinel appears and again each time the window grows, without threading the binding into every row.

#### Threshold Loading

Load earlier than the last item:

```swift
.onPaginationThreshold(threshold: 3, item: movie, in: $movies)
```

#### Custom Pagination Triggers

Use your own logic to trigger `loadMore()`:

```swift
.onPaginationTrigger(item: movie, in: $movies) { current, all in
  current.popularity > 8.0 && all.count > 10
}
```

### Staying Live

Because the window is backed by `@Query`, you don't need to do anything to keep results current — a row inserted, edited, or deleted anywhere against the same `ModelContext` is reflected automatically, including while the list is on screen.

Changing `filterPredicate` or `sortDescriptors` always re-executes the query correctly against the new arguments — there's no stale or duplicated data to worry about. The one thing that *doesn't* reset automatically is the **window size**: if you've scrolled deep into one filter and then switch to a different scope (a different parent record, a different tab), the new scope starts with however large the window had already grown. Call `reset()` if you want a clean small window on scope changes:

```swift
.onChange(of: selectedGenre) {
  $movies.reset()
}
```

### Checking Pagination Phase

```swift
switch $movies.phase {
case .idle:
  // more data may be available
case .complete:
  Text("All done!")
    .font(.footnote)
    .foregroundStyle(.secondary)
}
```

`hasReachedEnd` is also available directly as a `Bool` if you don't need to switch over `phase`.

`phase` returns `PaginationPhase`. The older name `Phase` is still available as a deprecated typealias for source compatibility.

## Logging

Toggle and customise logging to see what's going on:

```swift
@PagedQuery(fetchLimit: 20, logger: .default) var movies: [Movie]
```

Available logging options:

- `.none`: No logs
- `.default`: Logs all entries from the wrapper to console, under SimpleLogger's `.swiftData` category
- `.custom(MyCustomLogger())`: Provide your own logging system

Want a different SimpleLogger category for the default logger? Pass it explicitly via `.custom`:

```swift
@PagedQuery(fetchLimit: 20, logger: .custom(DefaultPaginationLogger(category: .myCategory))) var movies: [Movie]
```

> [!TIP]
> You can use your own logging system so you can also send information to crash aggregators or telemetry systems besides logging only to the user's device.

## Example

```swift
import SwiftUI
import SwiftData
import SwiftDataPager

struct MovieListView: View {
  @PagedQuery(
    fetchLimit: 100,
    sortDescriptors: [.init(\Movie.name)],
    filterPredicate: #Predicate { $0.name.localizedStandardContains("AU") },
    logger: .default
  ) private var movies: [Movie]

  var body: some View {
    NavigationStack {
      List {
        ForEach(movies) { movie in
          Text(movie.name)
            .onLoadMore(item: movie, in: $movies)
        }
      }
      .navigationTitle("Movies")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          if $movies.hasReachedEnd {
            Text("All done!")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }
}
```

### Video

Demo pagination of `10000` records.

[![SwiftDataPager Demo](https://img.youtube.com/vi/amlm-rkMVTI/maxresdefault.jpg)](https://www.youtube.com/watch?v=amlm-rkMVTI)

## Migrating from earlier versions

SwiftDataPager's internals changed from a manual, offset-based snapshot fetch to a live `@Query`-backed window. This is a breaking change:

- **Removed:** `isFetching`, `error`, `retry()`, `showFetching(in:)`, `onEmptyLoad(in:)`. Fetching is now synchronous and doesn't throw a recoverable error to the wrapper, so there's no in-flight state to show and nothing to retry — the first page is already loaded by the time your view's `body` runs.
- **Replaced:** the internal `PaginationState` is now a public `PaginationPhase` enum (`.idle` / `.complete`), accessible via `$movies.phase`. The prior name `Phase` remains as a deprecated typealias.
- **Unchanged:** `@PagedQuery(fetchLimit:sortDescriptors:filterPredicate:logger:)`, `wrappedValue`, `loadMore()`, `reset()`, `hasReachedEnd`, `onLoadMore(item:in:)`, `onPaginationThreshold(threshold:item:in:)`, `onPaginationTrigger(item:in:when:)` all keep the same call sites — `onLoadMore`/`onPaginationThreshold` no longer require `Equatable` on your model.
- **Added:** `@PagedQuery` now also takes an optional trailing `animation:` parameter, defaulting to `nil` — existing call sites keep compiling unchanged. A new `paginationSentinel(in:)` view modifier offers a one-task-for-the-whole-list alternative to `onLoadMore(item:in:)`.
- **Toolchain:** now requires Swift 6.2 / Xcode 26 or later (previously Swift 6.0), due to an isolated-conformance requirement in the new implementation.

## Contributing

Contributions are always welcome! Feel free to submit a pull request or open an issue for any suggestions or improvements you have.

## License

`SwiftDataPager` is licensed under the MIT License. See the LICENCE file for more details.
