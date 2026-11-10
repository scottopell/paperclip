//
//  LazyTextView.swift
//  spaperclip
//
//  Created by Scott Opell on 5/4/25.
//

import AppKit
import SwiftUI

/// An NSTextView wrapper that decodes clipboard text off the main thread and
/// updates AppKit once. NSTextView already supports non-contiguous layout, so
/// repeatedly rebuilding its entire string in artificial 50 KB increments only
/// adds quadratic copying and latency.
struct LazyTextView: NSViewRepresentable {
    let content: ClipboardContent
    let isEditable: Bool
    let maximumPreviewCharacters: Int?
    @Binding var isPreviewTruncated: Bool

    init(content: ClipboardContent, isEditable: Bool,
         maximumPreviewCharacters: Int? = nil,
         isPreviewTruncated: Binding<Bool> = .constant(false)) {
        self.content = content
        self.isEditable = isEditable
        self.maximumPreviewCharacters = maximumPreviewCharacters
        _isPreviewTruncated = isPreviewTruncated
    }

    /// Bound AppKit layout, not clipboard data. Even non-contiguous layout must
    /// shape an entire paragraph before it can display the first visible lines.
    struct Preview {
        static let maximumUTF16Length = 20_000
        let text: String
        let isTruncated: Bool

        init(_ text: String, maximumCharacters: Int?) {
            guard let maximumCharacters else {
                self.text = text
                isTruncated = false
                return
            }
            // Character count alone does not bound shaping: one grapheme may
            // contain arbitrarily many combining scalars. Omit a whole cluster
            // if it would exceed TextKit's UTF-16 budget.
            var end = text.startIndex
            var remainingUTF16 = Self.maximumUTF16Length
            for _ in 0..<maximumCharacters {
                guard end != text.endIndex else { break }
                let next = text.index(after: end)
                let size = text[end..<next].utf16.count
                guard size <= remainingUTF16 else { break }
                remainingUTF16 -= size
                end = next
            }
            self.text = String(text[..<end])
            isTruncated = end != text.endIndex
        }
    }

    final class TextLoadingCoordinator: NSObject {
        private let lock = NSLock()
        private var generation = UUID()
        var textLoadingTask: DispatchWorkItem?
        private(set) var isLoadingCancelled = false

        deinit {
            cancelLoading()
        }

        func beginLoading() -> UUID {
            lock.lock()
            defer { lock.unlock() }
            textLoadingTask?.cancel()
            generation = UUID()
            isLoadingCancelled = false
            return generation
        }

        func install(_ task: DispatchWorkItem, for candidate: UUID) {
            lock.lock()
            defer { lock.unlock() }
            guard generation == candidate, !isLoadingCancelled else {
                task.cancel()
                return
            }
            textLoadingTask = task
        }

        func shouldApply(_ candidate: UUID) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return !isLoadingCancelled
                && generation == candidate
                && textLoadingTask?.isCancelled != true
        }

        func cancelLoading() {
            lock.lock()
            defer { lock.unlock() }
            isLoadingCancelled = true
            textLoadingTask?.cancel()
            textLoadingTask = nil
            generation = UUID()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let loader = TextLoadingCoordinator()
        var currentContentID: UUID?

        deinit {
            loader.cancelLoading()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = isEditable
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.delegate = context.coordinator

        context.coordinator.currentContentID = content.id
        startTextLoading(in: textView, coordinator: context.coordinator)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.delegate = context.coordinator
        textView.isEditable = isEditable

        guard context.coordinator.currentContentID != content.id else { return }
        context.coordinator.currentContentID = content.id
        startTextLoading(in: textView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.loader.cancelLoading()
    }

    private func startTextLoading(in textView: NSTextView, coordinator: Coordinator) {
        let token = coordinator.loader.beginLoading()
        textView.string = "Loading content..."

        let content = content
        if content.usesLocalHTMLText {
            guard content.data.count <= LocalHTMLText.maximumImportBytes else {
                textView.string = "HTML preview unavailable above 2 MB. Original clipboard data is unchanged."
                return
            }
            RichSearchIndexer.shared.index(content, allowLarge: true) {
                [weak textView, weak coordinator] text in
                guard let textView, let coordinator,
                      coordinator.loader.shouldApply(token) else { return }
                loadPreview(in: textView, coordinator: coordinator, token: token) { text }
            }
            return
        }
        loadPreview(in: textView, coordinator: coordinator, token: token) { content.textForDisplay() }
    }

    private func loadPreview(in textView: NSTextView, coordinator: Coordinator, token: UUID,
                             decode: @escaping () -> String?) {
        let maximumCharacters = maximumPreviewCharacters
        let truncation = $isPreviewTruncated
        let loadingTask = DispatchWorkItem { [weak textView, weak coordinator] in
            let preview = Preview(decode() ?? "Unable to display text content.",
                                  maximumCharacters: maximumCharacters)
            guard let coordinator, coordinator.loader.shouldApply(token) else { return }

            DispatchQueue.main.async { [weak textView, weak coordinator] in
                guard let coordinator, coordinator.loader.shouldApply(token) else { return }
                textView?.string = preview.text
                truncation.wrappedValue = preview.isTruncated
            }
        }
        coordinator.loader.install(loadingTask, for: token)
        DispatchQueue.global(qos: .userInitiated).async(execute: loadingTask)
    }
}
