//
// Project: SwiftDataPager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import SwiftUI
import SwiftData

extension View {

    /// A helper that checks if the paginated query is ready to load more items.
    ///
    /// - Parameter paginated: The active `PagedQuery` instance.
    /// - Returns: `true` if calling `loadMore()` is allowed.
    private func canLoadMore<Model>(_ paginated: PagedQuery<Model>) -> Bool {
        !paginated.hasReachedEnd
    }

    /// Triggers a paginated fetch when the provided `item` is the last item in the current results.
    ///
    /// Typically used within a `ForEach` loop to automatically load more data as the user scrolls.
    ///
    /// - Parameters:
    ///   - item: The current item being rendered in the list.
    ///   - paginated: The active `PagedQuery` managing pagination state and data.
    /// - Returns: A `View` that runs a task when the specified item is rendered.
    public func onLoadMore<Model: PersistentModel>(
        item: Model,
        in paginated: PagedQuery<Model>
    ) -> some View {
        self.task(id: item.persistentModelID) {

            // Only proceed if the current item is the last one.
            guard paginated.wrappedValue.last?.persistentModelID == item.persistentModelID else {
                return
            }

            if canLoadMore(paginated) {
                paginated.logger.log("""
                onLoadMore triggered for last item:
                \(item.persistentModelID)
                """)
                paginated.loadMore()
            } else {
                paginated.logger.log("""
                onLoadMore condition met for item:
                \(item.persistentModelID)
                But skipping fetch — already at end.
                """)
            }
        }
    }

    /// Triggers a paginated load based on a custom condition.
    ///
    /// Allows fine-grained control over when `loadMore()` should be triggered, for example:
    /// detecting when a specific index is reached or a particular model appears in view.
    ///
    /// - Parameters:
    ///   - item: The item currently being rendered.
    ///   - paginated: The associated `PagedQuery` instance.
    ///   - condition: A closure that returns `true` when pagination should be triggered.
    /// - Returns: A modified `View` that runs the condition check as a task.
    public func onPaginationTrigger<Model: PersistentModel>(
        item: Model,
        in paginated: PagedQuery<Model>,
        when condition: @escaping (_ item: Model, _ allItems: [Model]) -> Bool
    ) -> some View {
        self.task(id: item.persistentModelID) {

            // Evaluate the custom condition.
            guard condition(item, paginated.wrappedValue) else { return }

            if canLoadMore(paginated) {
                paginated.logger.log("""
                onPaginationTrigger condition met for item:
                \(item.persistentModelID)
                """)
                paginated.loadMore()
            } else {
                paginated.logger.log("""
                onPaginationTrigger condition met for item:
                \(item.persistentModelID)
                But skipping fetch — already at end.
                """)
            }
        }
    }

    /// Triggers pagination when a given item is within a specified threshold from the end.
    ///
    /// Great for implementing "infinite scroll" with early fetches to avoid hitting the bottom.
    ///
    /// - Parameters:
    ///   - threshold: How many items from the end should trigger a load (minimum is 1).
    ///   - item: The item currently being rendered.
    ///   - paginated: The associated `PagedQuery` instance.
    /// - Returns: A modified `View` that evaluates the threshold and conditionally loads more.
    public func onPaginationThreshold<Model: PersistentModel>(
        threshold: Int,
        item: Model,
        in paginated: PagedQuery<Model>
    ) -> some View {

        // Ensure threshold is at least 1
        let effectiveThreshold = max(1, threshold)

        return self.onPaginationTrigger(item: item, in: paginated) { currentItem, allItems in

            // Check if there are any items and if we can find the index of the current item.
            guard !allItems.isEmpty, let index = allItems.firstIndex(where: {
                $0.persistentModelID == currentItem.persistentModelID
            }) else {
                paginated.logger.log("""
                    onPaginationThreshold could not find index for item:
                    \(item.persistentModelID)
                    """)
                return false
            }

            let targetIndex = allItems.count - effectiveThreshold
            let shouldLoad = index >= targetIndex

            if shouldLoad {
                paginated.logger.log("""
                onPaginationThreshold condition met:
                 - item index \(index) >= target index \(targetIndex)
                 - count: \(allItems.count)
                 - threshold: \(effectiveThreshold)
                """)
            }

            return shouldLoad
        }
    }
}
