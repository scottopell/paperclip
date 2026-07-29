# Paperclip Design Philosophy

Paperclip is a private, keyboard-first macOS utility for one loop:

> invoke → type → choose → return to work

Quick Search is the product. The full history window supports inspection, recovery, and configuration; it must not make the core loop slower, less reliable, or more complicated.

## Product laws

### 1. Disappear into the workflow

Paperclip should capture quietly, appear instantly, accept keyboard input immediately, restore the chosen item, and get out of the way. Protect focus, latency, deterministic selection, and keyboard navigation before adding secondary capability. Reject visual weight, setup, or concepts that leak into this path without earning their place.

### 2. Treat clipboard data as user data

Capture representations faithfully when practical. Enter restores all captured representations; explicit alternatives such as Shift+Enter may deliberately transform them. Never silently degrade, invent, upload, or mutate clipboard content. Failed operations must not pretend to succeed.

Clipboard history is local and private by default. No network access, telemetry, cloud processing, content analytics, or sync without a separately justified, explicit, opt-in product decision.

### 3. Follow macOS ownership boundaries

Use AppKit for application, window, menu-bar, focus, pasteboard, and controller lifecycle. Use SwiftUI to render views. Every long-lived resource must have one obvious owner whose lifetime matches the resource.

Prefer boring, documented macOS behavior over clever bridges. Do not build around timing guesses, arbitrary delays, scene resurrection, framework-private behavior, or incidental contents of `NSApplication.shared.windows`.

### 4. An ask requires a useful justification

The primary user drives priorities, but an explicit request opens consideration—it does not waive design scrutiny. Before adding meaningful complexity, state:

- who benefits and in what real workflow;
- why the simpler alternative is insufficient;
- what cost or risk the feature adds to the core loop.

If the justification is weak, challenge it concretely and offer a cheaper path. After an informed decision, commit fully and implement the smallest native solution. Do not create speculative abstractions, future-proofing, or feature scaffolding merely because they might become useful.

### 5. Prove behavior at stable boundaries

Test the user journey, not implementation trivia. Measure performance claims on the production path. Prefer pure unit tests for ranking and state transitions, and focused UI tests for focus, keyboard flow, and restoration. Do not hide flaky platform automation behind sleeps or test-only product behavior; document a manual acceptance check when macOS automation cannot reliably cross an OS boundary.

## Decision order

When principles conflict, decide in this order:

1. Preserve clipboard fidelity, privacy, and explicit user intent.
2. Protect the Quick Search loop and its responsiveness.
3. Follow native macOS lifecycle and ownership conventions.
4. Choose the smallest implementation with a clear owner.
5. Add broader capability only when its useful justification survives pushback.

Paperclip is not a clipboard platform. It is a sharp daily tool. Keep it trustworthy, immediate, native, and small.
