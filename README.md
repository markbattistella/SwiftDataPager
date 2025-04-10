<!-- markdownlint-disable MD024 MD033 MD041 -->
<div align="center">

# SwiftDataPager

<small>Effortless Pagination for SwiftData</small>

![Swift Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmarkbattistella%2FSwiftDataPager%2Fbadge%3Ftype%3Dswift-versions)

![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmarkbattistella%2FSwiftDataPager%2Fbadge%3Ftype%3Dplatforms)

![Licence](https://img.shields.io/badge/Licence-MIT-white?labelColor=blue&style=flat)

</div>

`SwiftDataPager` is a Swift package designed to simplify the process of implementing pagination with SwiftData.

Working with large datasets in `SwiftData` can be challenging when you want to load data incrementally. `SwiftDataPager` provides an easy-to-use API that handles all the complexity of pagination, allowing developers to focus on creating great user experiences rather than managing fetch offsets and pagination state.

By providing property wrappers and view modifiers, `SwiftDataPager` makes infinite scrolling and paginated data loading straightforward in SwiftUI applications.

## Features

## Installation

Add `SwiftDataPager` to your Swift project using Swift Package Manager.

```swift
dependencies: [
  .package(url: "https://github.com/markbattistella/SwiftDataPager", from: "1.0.0")
]
```

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
  logger: .default
) var actionMovies: [Movie]
```

## View Modifiers

`SwiftDataPager` comes with several view modifiers to make pagination even easier:

### Automatic Loading on Last Item

> [!WARNING]  
> The `.onLoadMore(item:, in:)` is a **required** modifier on each cell item. This helps identify when we have reached the limit, and fetch new results. It has been optimised to exit early if not required to fetch.

```swift
ForEach(movies) { movie in
    MovieRow(movie: movie)
        .onLoadMore(item: movie, in: $movies)
}
```

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

#### Loading Indicators

Display a loading spinner during fetch:

```swift
if $movies.isFetching {
  ProgressView()
    .showFetching(in: $movies)
}
```

#### Auto Load on Appear

Great for empty states:

```swift
List {
  // List content
}
.onEmptyLoad(in: $movies)
```

### Error Handling

SwiftDataPager provides error state tracking to handle fetch failures gracefully:

```swift
if let error = $movies.error {
  Text("Failed to load: \(error.localizedDescription)")
  Button("Retry") { $movies.retry() }
}
```

### Resetting Pagination

You can reset pagination to start fresh:

```swift
Button("Reset") {
  $movies.reset()
}
```

## Logging

Toggle and customise logging to see what's going on:

```swift
@PagedQuery(fetchLimit: 20, logger: .default) var movies: [Movie]
```

Available logging options:

- `.none`: No logs
- `.default`: Logs all entries from the wrapper to console
- `.custom(MyCustomLogger())`: Provide your own logging system

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
    filterPredicate: #Predicate { $0.name.contains("AU") },
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
        ToolbarItem(placement: .topBarLeading) {
          if $items.isFetching {
            ProgressView()
              .showFetching(in: $items)
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          if $items.hasReachedEnd {
            Text("All done!")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }
        ToolbarItem(placement: .bottomBar) {
          if let error = $items.error {
            Text("Error: \(error.localizedDescription)")
              .foregroundColor(.red)
          }
        }
      }
    }
  }
}
```

### Video

Demo pagination of `10000` records.

https://github.com/user-attachments/assets/ae23a398-b28c-4bed-9fee-7d244a142b44

## Contributing

Contributions are always welcome! Feel free to submit a pull request or open an issue for any suggestions or improvements you have.

## License

`SwiftDataPager` is licensed under the MIT License. See the LICENCE file for more details.
