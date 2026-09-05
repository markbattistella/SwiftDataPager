//
// Project: SwiftDataPager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

/// The current phase of a `PagedQuery`'s pagination window.
public enum Phase: Equatable, Sendable {

  /// More data may be available; `loadMore()` will grow the window.
  case idle

  /// The fetch window already covers every row matching the current predicate/sort.
  case complete
}
