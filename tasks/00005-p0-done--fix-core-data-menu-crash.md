# Fix Core Data menu-bar crash

## Diagnosis

Opening the menu-bar popover dispatches statistics collection to a global user-initiated queue. `getStoreStatistics()` then fetches and traverses managed objects using `persistentContainer.viewContext`, which is main-queue confined. The supplied crash report shows Core Data unregistering managed objects concurrently on the main thread and that global queue, ending in `_PFObjectIDFastHash64` with `EXC_BAD_ACCESS`.

## Plan

1. Make statistics collection asynchronous and context-owned.
2. Create a private-queue context for each statistics request and perform every fetch/relationship traversal on its queue.
3. Return only immutable value data to the main actor; never return managed objects or contexts.
4. Prevent overlapping refresh requests from racing UI state.
5. Add regression coverage and run with Core Data concurrency debugging enabled where possible.
6. Validate menu-bar open/refresh and the full unit suite.

## Resolution

The original menu-bar crash was an application queue-confinement violation: statistics work ran on a global queue but fetched and traversed relationships through the main-queue `viewContext`. Statistics now use a dedicated private-queue context, keep all managed objects inside `context.perform`, reset that context before returning, and expose only a `Sendable` value snapshot to SwiftUI.

The first regression test accidentally opened the separate application-menu statistics window and produced `crash2.txt`, a distinct AppKit constraint-update exception. That window now uses an `NSHostingController` with automatic window sizing disabled so SwiftUI state changes cannot resize it during AppKit's layout cycle.

Validation under `-com.apple.CoreData.ConcurrencyDebug 1`:

- Status-item popover opens and loads statistics.
- Five repeated refresh attempts complete without a queue violation or crash.
- The application-menu statistics window opens after closing the popover.
- Full unit suite passes.
