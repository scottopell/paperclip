# Red-first TDD: fix two clipboard correctness bugs

## Summary

Two correctness bugs in `spaperclip/ClipboardMonitor.swift` are silently broken and uncovered by the existing suite. This task drives the fix with **red-first** tests: add failing tests that pin each bug, watch them fail for the documented reason, then make them green with the minimal fix.

## Bug 1 — Large multi-byte text chunking is broken

**Site:** `ClipboardContent.getTextChunk(offset:length:)`, the `data.count >= 100_000` branch (`ClipboardMonitor.swift:206–232`), plus `String.Encoding.characterWidth` (`:869–884`).

**Root cause:** The API is character-based (small branch slices with `fullText.index(startIndex, offsetBy: offset)`; return is `(text, offset + chunkText.count)`). The large branch computes `startByte = offset * encoding.characterWidth`, and `characterWidth` returns `1` for `.utf8`. For multi-byte UTF-8 text the character offset is treated as a byte offset, so `startByte` lands mid-code-unit. `String(data:encoding:.utf8)` is strict and returns `nil`, so `getTextChunk` returns `nil` for almost every non-zero offset. When it accidentally lands on a boundary, `loadBytes = length * 1 + 16` loads far fewer characters than requested and `nextOffset` advances by the wrong amount, corrupting iterative reconstruction.

The suite misses it because `TextChunkingTests`/`TextHandlingTests` only feed ASCII into the large path (`String(repeating: "abcdefghij", ...)`), and the multi-byte tests build strings small enough (~2.5 KB) to take the small-text branch.

### Red test (add to `spaperclipTests/TextChunkingTests.swift`)

```swift
func testLargeMultiByteTextReconstruction() throws {
    // Build multi-byte text large enough to exceed the 100 KB small-text threshold.
    let unit = "Hello 🌍 World! こんにちは 世界! Здравствуй мир! 👋👨‍👩‍👧‍👦\n"
    let largeText = String(repeating: unit, count: 4_000)  // > 100 KB of UTF-8
    let data = largeText.data(using: .utf8)!

    let content = ClipboardContent(
        data: data,
        formats: [ClipboardFormat(uti: UTType.plainText.identifier)],
        description: "Large multi-byte"
    )

    var offset = 0
    var reconstructed = ""
    while offset < largeText.count {
        guard let (chunk, nextOffset) = content.getTextChunk(offset: offset, length: 1_000) else {
            XCTFail("getTextChunk returned nil at offset \(offset)")
            return
        }
        XCTAssertGreaterThan(nextOffset, offset, "must make progress at offset \(offset)")
        reconstructed += chunk
        offset = nextOffset
    }
    XCTAssertEqual(reconstructed, largeText, "reconstructed text must match original")
}
```

**Expected red:** `getTextChunk` returns `nil` once `offset` advances past the first byte window (startByte lands mid-code-unit), so the test fails at the `XCTFail("getTextChunk returned nil at offset …")` line. (At `offset == 0` the first call happens to succeed because `startByte == 0` is a valid boundary, but the second call with `offset` equal to the first chunk's character count computes a mid-character `startByte` and decodes `nil`.)

### Green fix

Stop using `characterWidth` as a byte multiplier for variable-width encodings. Decode the whole `Data` once and slice by `String.Index` (character offset), the same model as the small branch; or over-allocate bytes and resync to the nearest valid UTF-8 boundary, returning `nextOffset` as the actual decoded character count. Keep the public contract character-based.

## Bug 2 — Re-copying a duplicate loses the "current clipboard" indicator

**Site:** `ClipboardMonitor.updateFromClipboard`, `ClipboardMonitor.swift:754–803`.

**Root cause:** `currentItem`/`currentItemID` are set to the freshly-built `newItem` (lines 764–765) before the duplicate check. In the duplicate branch (781–792) the existing item is moved to the top of `history` and `selectedHistoryItem` is updated, but `currentItem`/`currentItemID` are left pointing at `newItem`, whose UUID was never inserted into `history`. `HistoryList` keys the green dot and green card border on `monitor.currentItemID == item.id` (`HistoryList.swift:121`, `:131`), so after a duplicate re-copy no row matches and the "current clipboard" indicator disappears until the next non-duplicate copy.

### Red test (add to a new `spaperclipTests/ClipboardMonitorDuplicateTests.swift`)

```swift
import UniformTypeIdentifiers
import XCTest
@testable import spaperclip

@MainActor
final class ClipboardMonitorDuplicateTests: XCTestCase {
    private func makeItem(text: String) -> ClipboardHistoryItem {
        ClipboardHistoryItem(
            timestamp: Date(),
            contents: [
                ClipboardContent(
                    data: text.data(using: .utf8)!,
                    formats: [ClipboardFormat(uti: UTType.plainText.identifier)],
                    description: text
                )
            ],
            sourceApplication: nil
        )
    }

    func testDuplicateReCopyKeepsCurrentItemIndicatorOnTopItem() {
        let monitor = ClipboardMonitor()

        // Seed history with one item (bypass the live pasteboard).
        let first = makeItem(text: "hello")
        monitor.history = [first]
        monitor.currentItem = first
        monitor.currentItemID = first.id

        // Simulate the user re-copying the *same* content from another app,
        // i.e. a duplicate newItem built from the same data.
        let duplicate = makeItem(text: "hello")

        // Drive the same logic updateFromClipboard runs on the main queue.
        // The production code sets currentItem/currentItemID to the new item
        // first, then detects the duplicate and moves the existing item to
        // the top. This test asserts the post-condition the UI relies on.
        let isDuplicate = monitor.history.contains { $0 == duplicate }
        XCTAssertTrue(isDuplicate, "sanity: duplicate should match existing item")

        if let index = monitor.history.firstIndex(where: { $0 == duplicate }) {
            let existing = monitor.history.remove(at: index)
            monitor.history.insert(existing, at: 0)
            monitor.selectedHistoryItem = existing
            // BUG: production code does NOT reset currentItem/currentItemID here.
        }

        // The current-clipboard indicator must point at a row that exists in history.
        let currentID = monitor.currentItemID
        XCTAssertNotNil(
            monitor.history.first(where: { $0.id == currentID }),
            "currentItemID must reference an item present in history"
        )
        XCTAssertEqual(
            monitor.history.first?.id, currentID,
            "the top history row must be the current item"
        )
    }
}
```

**Expected red:** After the duplicate branch runs, `monitor.currentItemID` still equals `duplicate.id` (set earlier in `updateFromClipboard`), which is not in `history`; the `currentItemID must reference an item present in history` assertion fails.

> Note: this test mirrors the production branch directly because `updateFromClipboard` reads `NSPasteboard.general` and is private. If preferred, the task can instead expose a testable `processNewHistoryItem(_:)` hook (or make `updateFromClipboard` internal) and assert on real behavior rather than a mirrored branch. Either way the red assertion is identical.

### Green fix

In the duplicate branch of `updateFromClipboard`, after moving `existingItem` to the top:

```swift
self.currentItem = existingItem
self.currentItemID = existingItem.id
```

Optionally also update `existingItem.timestamp = newItem.timestamp` so "most recent" reflects the re-copy.

## Execution plan

1. Add the two red tests above.
2. Run `swift test` (or the Xcode test action) and confirm both fail for the documented reasons — capture the failure output as evidence.
3. Apply the minimal green fixes.
4. Re-run the suite; confirm both new tests pass and no existing tests regress.
5. Add a brief `## Resolution` section to this task file summarizing the diff and the evidence captured in step 2.

## Scope guardrails

- No refactors beyond the minimal fixes.
- Do not change the `getTextChunk` public signature (character-based offset/length/nextOffset).
- Do not change `HistoryList`/`HistoryItemRow` display contracts; Bug 2 is fixed at the monitor.
- Keep the existing ASCII large-text tests green.

## Resolution

Both bugs fixed with minimal changes in `spaperclip/ClipboardMonitor.swift`; tests added in `spaperclipTests/TextChunkingTests.swift` and a new `spaperclipTests/ClipboardMonitorDuplicateTests.swift`.

### Bug 1 — large multi-byte text chunking

Replaced byte-offset math with a thread-safe, one-time decode cache plus `String.Index` slices. Multi-byte characters are never split, repeated chunk reads do not repeatedly decode the full payload, and `nextOffset` remains character-based.

Red evidence (chunking fix reverted, equality fix in place):
```
TextChunkingTests.testLargeMultiByteTextReconstruction: failed - getTextChunk returned nil at offset 889
```
Green after fix: `testLargeMultiByteTextReconstruction` passes; all existing ASCII large-text tests still pass.

### Bug 2 — duplicate detection + current-item indicator

Investigation revealed a deeper root cause than the approved plan described: `ClipboardFormat` conformed to `Identifiable, Hashable` with `let id = UUID()`, so the synthesized `Equatable`/`Hashable` keyed on the per-instance UUID. Two `ClipboardFormat(uti: "public.plain-text")` were therefore never equal, which made `ClipboardContent.==` and `ClipboardHistoryItem.==` almost always false, which made `isDuplicate` in `updateFromClipboard` always false — so the duplicate branch was effectively dead code and re-copying identical content inserted duplicate history entries instead of moving the existing item to the top.

Fix: `ClipboardFormat` keeps a UUID for stable SwiftUI identity while `==`/`hash` compare only `uti`. Duplicate application moved into `applyHistoryItem`, the same production method used by pasteboard capture and tests. Matching uses reproducible clipboard representations; promotion preserves the existing row identity and source attribution, refreshes its timestamp, and resets `currentItem`/`currentItemID` to that row.

Red evidence (equality fix reverted, chunking fix in place):
```
ClipboardMonitorDuplicateTests.testIdenticalContentsAreEqual: XCTAssertEqual failed - items with identical data and formats must be equal
ClipboardMonitorDuplicateTests.testDuplicateReCopyKeepsCurrentItemIndicatorOnTopItem: XCTAssertTrue failed - sanity: duplicate should match existing item
```
Green after fix: both new tests pass.

### Final suite

`xcodebuild -only-testing:spaperclipTests test` → **TEST SUCCEEDED** — 51 tests, 0 failures after rebasing onto current `origin/main`. Regression coverage exercises the real monitor path, representation matching, source attribution, stable view identity, and large multi-byte chunking.

### Files changed

- `spaperclip/ClipboardMonitor.swift` — semantic format equality with UUID view identity; cached text decoding; testable production history application; order-independent payload matching.
- `spaperclipTests/TextChunkingTests.swift` — large multi-byte reconstruction regression.
- `spaperclipTests/ClipboardMonitorDuplicateTests.swift` — real monitor-path tests for dedupe, current-item state, ordering, source attribution, and identity/equality separation.
