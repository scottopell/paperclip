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
        let loadingTask = DispatchWorkItem { [weak textView, weak coordinator] in
            let text = content.textForDisplay()
            guard let coordinator, coordinator.loader.shouldApply(token) else { return }

            DispatchQueue.main.async { [weak textView, weak coordinator] in
                guard let coordinator, coordinator.loader.shouldApply(token) else { return }
                textView?.string = text ?? "Unable to display text content."
            }
        }
        coordinator.loader.install(loadingTask, for: token)
        DispatchQueue.global(qos: .userInitiated).async(execute: loadingTask)
    }
}
