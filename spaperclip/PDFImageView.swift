//
//  PDFImageView.swift
//  spaperclip
//
//  Created by Scott Opell on 5/4/25.
//

import SwiftUI
import PDFKit

/// PDFKit provides the zoom and pan gestures for image previews.
struct PDFImageView: View {
    let data: Data
    let contentID: UUID

    @State private var loadedDocument: (id: UUID, document: PDFDocument)?
    @State private var failedContentID: UUID?

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
        .task(id: contentID) {
            loadedDocument = nil
            failedContentID = nil
            let imageData = data
            let document = await Task.detached(priority: .userInitiated) { () -> PDFDocument? in
                guard let image = NSImage(data: imageData),
                    let page = PDFPage(image: image)
                else { return nil }
                let document = PDFDocument()
                document.insert(page, at: 0)
                return document
            }.value
            guard !Task.isCancelled else { return }
            if let document {
                loadedDocument = (contentID, document)
            } else {
                failedContentID = contentID
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
