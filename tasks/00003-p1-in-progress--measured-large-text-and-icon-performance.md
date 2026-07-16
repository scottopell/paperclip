# Deliver only measured large-text and icon performance wins

## Evidence and scope

Keep only the two candidates that produced clear, repeatable wins on an Apple M1 Max with optimized Swift code. Do not pursue search caching: the benchmark showed only 1.28x at 1 KB/item and 1.01x at 100 KB/item, so it is explicitly out of scope.

### Accepted candidate 1: large plain-text detail rendering

The current `LazyTextView` processes 1 MB in 50 KB chunks, sleeps 50 ms after every chunk, reads the entire current `NSTextView.string`, concatenates it, and replaces the entire text on every iteration.

Five-sample controlled benchmark:

- Current algorithm: 1549.65, 1604.95, 1691.75, 1591.28, 1568.37 ms; median **1591.28 ms**
- Single background-style decode plus one `NSTextView` assignment: 6.99, 5.90, 5.54, 5.70, 6.41 ms; median **5.90 ms**
- Measured candidate improvement: **269.6x**

### Accepted candidate 2: source-application icon caching

`SourceApplicationInfo.applicationIcon` currently resolves the application URL and bundle and requests its icon on every property read. SwiftUI rows and detail views read this computed property repeatedly as selection causes rerenders.

Nine-sample controlled benchmark for 100 Finder icon reads:

- Re-resolve each read: 33.12, 28.20, 36.94, 57.58, 19.10, 22.33, 18.13, 21.96, 19.58 ms; median **22.33 ms**
- Cached read: below timer resolution in the synthetic loop

Treat **22.33 ms eliminated per 100 repeated resolutions** as the meaningful result; do not claim the synthetic ratio.

## Implementation plan

1. Add focused release-mode performance harnesses around the production large-text loading algorithm and application-icon lookup/cache path. Record raw samples and medians; do not rely on a single run.
2. Refactor `LazyTextView` so background work decodes/builds large plain text without arbitrary sleeps or repeated whole-document reads/replacements. Publish to AppKit on the main thread with cancellation and content-identity checks so a stale load cannot overwrite a newer selection.
3. Preserve rendering correctness for small text, large ASCII/UTF-8 text, cancellation, rapid item switching, and empty/failed decoding. Keep AppKit mutation on the main thread.
4. Cache source-app icons by bundle identifier in a bounded/shared cache. Preserve the generic clipboard fallback and avoid persisting duplicate icon blobs in each in-memory history item.
5. Add functional regression tests for large-text output, cancellation/stale-load protection, and cache hit behavior.
6. Run optimized before/after benchmarks with one warmup and at least five measured samples, plus the full unit-test suite. Retain each optimization only if its median improvement is reproducible and output is identical.

## Acceptance gates

- 1 MB plain-text detail loading median is at least **10x faster** than baseline and below **160 ms** on the same machine/load conditions. The exploratory candidate measured 5.90 ms, so this gate leaves substantial noise margin.
- 100 repeated source-icon reads have a median below **2.25 ms** (at least **10x faster** than the 22.33 ms baseline).
- Benchmarks report raw per-run samples, median, workload, build configuration, hardware, and before/after commit identifiers.
- Loaded text is byte/character-equivalent for supported inputs; rapid selection cannot display stale content.
- Existing unit tests pass.
- Any candidate that misses its gate is reverted rather than justified speculatively.
