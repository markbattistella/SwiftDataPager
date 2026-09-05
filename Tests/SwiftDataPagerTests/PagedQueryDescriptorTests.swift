//
// Project: SwiftDataPager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Foundation
import SwiftData
import Testing

@testable import SwiftDataPager

@Model
final class PagedQueryTestItem {
  var order: Int
  init(order: Int) { self.order = order }
}

/// Boundary-math coverage for the window+1 "peek row" trick `PagedQuery` uses to answer
/// `hasReachedEnd` without a separate `fetchCount` query.
///
/// This tests the descriptor-building logic directly against a plain, in-memory
/// `ModelContext` — no `View`/`DynamicProperty` involved. True `@Query` reactivity (live
/// updates via `update()`) needs a rendered SwiftUI view and isn't covered here; see the
/// README's testing note for that gap.
@Suite("PagedQuery descriptor boundary math")
struct PagedQueryDescriptorTests {

  private func makeContext(itemCount: Int) throws -> ModelContext {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: PagedQueryTestItem.self, configurations: configuration)
    let context = ModelContext(container)
    for order in 0..<itemCount {
      context.insert(PagedQueryTestItem(order: order))
    }
    try context.save()
    return context
  }

  @Test("Fewer items than the window: no peek row, all items returned")
  func fewerItemsThanWindow() throws {
    let context = try makeContext(itemCount: 3)
    let window = 10
    let descriptor = PagedQuery<PagedQueryTestItem>.descriptor(
      window: window,
      predicate: nil,
      sortDescriptors: [SortDescriptor(\.order)]
    )
    let results = try context.fetch(descriptor)

    #expect(results.count == 3)
    #expect(results.count <= window, "hasReachedEnd should read true")
  }

  @Test("Exactly window items: no peek row, hasReachedEnd is true")
  func exactlyWindowItems() throws {
    let context = try makeContext(itemCount: 10)
    let window = 10
    let descriptor = PagedQuery<PagedQueryTestItem>.descriptor(
      window: window,
      predicate: nil,
      sortDescriptors: [SortDescriptor(\.order)]
    )
    let results = try context.fetch(descriptor)

    #expect(results.count == 10)
    #expect(results.count <= window, "hasReachedEnd should read true")
  }

  @Test("More items than the window: the peek row is present, hasReachedEnd is false")
  func moreItemsThanWindow() throws {
    let context = try makeContext(itemCount: 25)
    let window = 10
    let descriptor = PagedQuery<PagedQueryTestItem>.descriptor(
      window: window,
      predicate: nil,
      sortDescriptors: [SortDescriptor(\.order)]
    )
    let results = try context.fetch(descriptor)

    #expect(results.count == window + 1, "the extra peek row should be fetched")
    #expect(results.count > window, "hasReachedEnd should read false")
    #expect(Array(results.prefix(window)).count == window, "wrappedValue trims the peek row")
  }

  @Test("Empty store: no items, hasReachedEnd is true")
  func emptyStore() throws {
    let context = try makeContext(itemCount: 0)
    let window = 10
    let descriptor = PagedQuery<PagedQueryTestItem>.descriptor(
      window: window,
      predicate: nil,
      sortDescriptors: []
    )
    let results = try context.fetch(descriptor)

    #expect(results.isEmpty)
    #expect(results.count <= window, "hasReachedEnd should read true")
  }

  @Test("Predicate excludes everything: empty result despite data being present")
  func predicateExcludesEverything() throws {
    let context = try makeContext(itemCount: 5)
    let window = 10
    let predicate = #Predicate<PagedQueryTestItem> { $0.order > 1_000 }
    let descriptor = PagedQuery<PagedQueryTestItem>.descriptor(
      window: window,
      predicate: predicate,
      sortDescriptors: []
    )
    let results = try context.fetch(descriptor)

    #expect(results.isEmpty)
    #expect(results.count <= window, "hasReachedEnd should read true")
  }

  @Test("Growing the window reveals the next page without losing earlier rows")
  func growingWindowRevealsNextPage() throws {
    let context = try makeContext(itemCount: 25)
    let sort = [SortDescriptor<PagedQueryTestItem>(\.order)]

    let firstDescriptor = PagedQuery<PagedQueryTestItem>.descriptor(
      window: 10,
      predicate: nil,
      sortDescriptors: sort
    )
    let firstPage = try context.fetch(firstDescriptor)
    #expect(Array(firstPage.prefix(10)).map(\.order) == Array(0..<10))

    let secondDescriptor = PagedQuery<PagedQueryTestItem>.descriptor(
      window: 20,
      predicate: nil,
      sortDescriptors: sort
    )
    let secondPage = try context.fetch(secondDescriptor)
    #expect(Array(secondPage.prefix(20)).map(\.order) == Array(0..<20))
    #expect(secondPage.count == 21, "still one peek row beyond the new window")
  }
}
