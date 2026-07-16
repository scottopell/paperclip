# Deliver a measured Quick Search latency win

## Scope

Measure the in-process query pipeline, avoiding XCUITest typing/accessibility overhead. Retain only changes that improve query-to-results latency while preserving result order, selection, keyboard navigation, and restore behavior.

## Acceptance gates

- Record one warmup and at least five raw before/after samples.
- Query-to-results median for a 100-item history must be below 50 ms and at least 5x faster than baseline.
- Filtering happens once per query update in Quick Search.
- Existing unit and Quick Search UI journey tests pass.
- Revert candidates that miss the gate.

## Delivered evidence

Apple M1 Max, Debug test host, one warmup plus five serial samples over 100 items:

- Existing 300 ms debounced query pipeline: 301.852, 302.141, 302.093, 307.463, 301.958 ms; median **302.093 ms**.
- Immediate single-pass query pipeline: 0.251, 0.218, 0.216, 0.216, 0.215 ms; median **0.216 ms**.
- Measured improvement: **about 1,398x**, with identical ordered result IDs.

Quick Search now computes one result snapshot per query, uses that snapshot for list rendering, selection, arrow navigation, and restore validation, and leaves the main-window search debounce unchanged.

Validation:

- Full unit suite passes.
- Quick Search keyboard journey passes, including focus, filtering, arrow navigation, restore, reinvocation reset, and escape.
- Quick Search plain-text restore journey passes.
