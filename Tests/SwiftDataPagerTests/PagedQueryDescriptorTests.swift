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

/// Boundary-math coverage for `PagedQuery`'s fixed, `maxWindow`-capped fetch descriptor.
///
/// This tests the descriptor-building logic directly against a plain, in-memory
/// `ModelContext` — no `View`/`DynamicProperty` involved. True `@Query` reactivity (live
/// updates via `update()`) needs a rendered SwiftUI view and isn't covered here; see the
/// README's testing note for that gap.
///
/// Runs serialized rather than Swift Testing's default parallel execution: each test creates
/// its own in-memory `ModelContainer`, and concurrent `ModelContainer` creation is a known
/// source of crashes in SwiftData's underlying store stack.
@Suite("PagedQuery descriptor boundary math", .serialized)
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

    @Test("Fewer items than maxWindow: every matching row is fetched")
    func fewerItemsThanMaxWindow() throws {
        let context = try makeContext(itemCount: 3)
        let maxWindow = 10
        let descriptor = PagedQuery<PagedQueryTestItem>.descriptor(
            maxWindow: maxWindow,
            predicate: nil,
            sortDescriptors: [SortDescriptor(\.order)]
        )
        let results = try context.fetch(descriptor)

        #expect(results.count == 3)

        let window = 10
        #expect(results.count <= window, "hasReachedEnd should read true")
    }

    @Test("More items than maxWindow: the fetch is capped, further rows are invisible")
    func moreItemsThanMaxWindow() throws {
        let context = try makeContext(itemCount: 25)
        let maxWindow = 10
        let descriptor = PagedQuery<PagedQueryTestItem>.descriptor(
            maxWindow: maxWindow,
            predicate: nil,
            sortDescriptors: [SortDescriptor(\.order)]
        )
        let results = try context.fetch(descriptor)

        #expect(results.count == maxWindow, "fetch is capped at maxWindow, not the true 25 rows")
        #expect(Array(results.map(\.order)) == Array(0..<maxWindow))
    }

    @Test("Empty store: no items, hasReachedEnd is true")
    func emptyStore() throws {
        let context = try makeContext(itemCount: 0)
        let descriptor = PagedQuery<PagedQueryTestItem>.descriptor(
            maxWindow: 10,
            predicate: nil,
            sortDescriptors: []
        )
        let results = try context.fetch(descriptor)

        #expect(results.isEmpty)

        let window = 10
        #expect(results.count <= window, "hasReachedEnd should read true")
    }

    @Test("Predicate excludes everything: empty result despite data being present")
    func predicateExcludesEverything() throws {
        let context = try makeContext(itemCount: 5)
        let predicate = #Predicate<PagedQueryTestItem> { $0.order > 1_000 }
        let descriptor = PagedQuery<PagedQueryTestItem>.descriptor(
            maxWindow: 10,
            predicate: predicate,
            sortDescriptors: []
        )
        let results = try context.fetch(descriptor)

        #expect(results.isEmpty)

        let window = 10
        #expect(results.count <= window, "hasReachedEnd should read true")
    }

    @Test("Growing the window client-side reveals more of the same fetched rows")
    func growingWindowRevealsNextPage() throws {
        let context = try makeContext(itemCount: 25)
        let sort = [SortDescriptor<PagedQueryTestItem>(\.order)]

        // The descriptor is built once, sized to maxWindow — it never changes as the window
        // grows. Only the client-side `prefix(window)` changes between "pages".
        let descriptor = PagedQuery<PagedQueryTestItem>.descriptor(
            maxWindow: 20,
            predicate: nil,
            sortDescriptors: sort
        )
        let rawItems = try context.fetch(descriptor)
        #expect(rawItems.count == 20, "fetch is capped at maxWindow")

        let firstPage = Array(rawItems.prefix(10))
        #expect(firstPage.map(\.order) == Array(0..<10))

        let secondPage = Array(rawItems.prefix(20))
        #expect(secondPage.map(\.order) == Array(0..<20))
    }

    @Test("hasReachedEnd semantics: rawItems.count <= window")
    func hasReachedEndSemantics() throws {
        let context = try makeContext(itemCount: 25)
        let sort = [SortDescriptor<PagedQueryTestItem>(\.order)]
        let maxWindow = 20
        let descriptor = PagedQuery<PagedQueryTestItem>.descriptor(
            maxWindow: maxWindow,
            predicate: nil,
            sortDescriptors: sort
        )
        let rawItems = try context.fetch(descriptor)
        #expect(rawItems.count == maxWindow, "fetch capped below the true 25 rows")

        // Below the ceiling: more of the fetched rows remain to reveal.
        #expect(rawItems.count > 10, "hasReachedEnd should read false at window 10")

        // At the ceiling: no further rows are visible, even though 25 rows truly exist.
        #expect(rawItems.count <= maxWindow, "hasReachedEnd should read true once window reaches maxWindow")
    }
}
