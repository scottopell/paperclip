//
//  PDFImageView.swift
//  spaperclip
//
//  Created by Scott Opell on 5/4/25.
//

import SwiftUI
import PDFKit

/// At most two decodes across preview views, with one replacement per view.
/// PDFKit's synchronous conversions cannot be interrupted; obsolete results
/// are discarded between stages.
final class ImagePreviewWorker: @unchecked Sendable {

    private struct Request {
        let ticket: UUID
        let data: Data
        let completion: (UUID, PDFDocument?) -> Void
    }

    private let lock = NSLock()
    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.scottopell.spaperclip.image-preview"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()
    private var current: UUID?
    private var pending: Request?
    private var working = false

    func load(data: Data, completion: @escaping (UUID, PDFDocument?) -> Void) -> UUID {
        let ticket = UUID()
        lock.lock()
        current = ticket
        pending = Request(ticket: ticket, data: data, completion: completion)
        if !working {
            working = true
            Self.queue.addOperation { [self] in drain() }
        }
        lock.unlock()
        return ticket
    }

    func cancel(_ ticket: UUID) {
        lock.lock()
        if current == ticket {
            current = nil
            pending = nil
        }
        lock.unlock()
    }

    private func isCurrent(_ ticket: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return current == ticket
    }

    private func drain() {
        lock.lock()
        guard let request = pending else {
            working = false
            lock.unlock()
            return
        }
        pending = nil
        lock.unlock()

        var document: PDFDocument?
        if isCurrent(request.ticket), let image = NSImage(data: request.data),
           isCurrent(request.ticket), let page = PDFPage(image: image),
           isCurrent(request.ticket) {
            let result = PDFDocument()
            result.insert(page, at: 0)
            document = result
        }

        // Do not start the next decode until the old result has been delivered or
        // discarded. This also bounds documents waiting on a busy main queue.
        DispatchQueue.main.async { [self] in
            if isCurrent(request.ticket) {
                request.completion(request.ticket, document)
            }
            Self.queue.addOperation { [self] in drain() }
        }
    }
}

/// PDFKit provides the zoom and pan gestures for image previews.
struct PDFImageView: View {
    let data: Data
    let contentID: UUID

    @State private var loadedDocument: (id: UUID, document: PDFDocument)?
    @State private var failedContentID: UUID?
    @State private var ticket: UUID?
    @State private var worker = ImagePreviewWorker()

    var body: some View {
        Group {
            if failedContentID == contentID {
                Text("Unable to preview image")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DocumentView(document: loadedDocument?.id == contentID ? loadedDocument?.document : nil)
            }
        }
        .onAppear { loadPreview() }
        .onChange(of: contentID) { _, _ in loadPreview() }
        .onDisappear {
            if let ticket { worker.cancel(ticket) }
            ticket = nil
            loadedDocument = nil
        }
    }

    private func loadPreview() {
        if let ticket { worker.cancel(ticket) }
        loadedDocument = nil
        failedContentID = nil
        let id = contentID
        ticket = worker.load(data: data) { resultTicket, document in
            guard ticket == resultTicket, contentID == id else { return }
            if let document {
                loadedDocument = (id, document)
            } else {
                failedContentID = id
            }
        }
    }

    private struct DocumentView: NSViewRepresentable {
        let document: PDFDocument?

        func makeNSView(context: Context) -> PDFView {
            let view = PDFView()
            view.autoScales = true
            view.displayMode = .singlePage
            view.displayDirection = .vertical
            return view
        }

        func updateNSView(_ view: PDFView, context: Context) {
            if view.document !== document {
                view.document = document
            }
        }
    }
}
