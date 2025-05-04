//
//  PDFImageView.swift
//  spaperclip
//
//  Created by Scott Opell on 5/4/25.
//

import SwiftUI
import PDFKit

// MARK: - Views

/// PDFImageView leverages PDFKit as an overpowered image viewer
// The main reasons for this are the built-in handling of zoom/pan gestures
// Overall highly recommend, but there are some un-addressed PDFKit warnings
// that mean I may not be using the APIs entirely correctly, but :shrug:
struct PDFImageView: NSViewRepresentable {
    let image: NSImage
    @State private var document: PDFDocument? = nil

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()

        // Configure the view
        view.autoScales = true
        view.displayMode = .singlePage
        view.displayDirection = .vertical

        // Start the document creation process
        createDocumentAsync()

        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        // Apply document when it becomes available
        if let doc = document {
            nsView.document = doc
        }
    }

    private func createDocumentAsync() {
        // Use background QoS to avoid priority inversion
        DispatchQueue.global(qos: .background).async {
            let doc = PDFDocument()
            if let page = PDFPage(image: image) {
                doc.insert(page, at: 0)
            }

            DispatchQueue.main.async {
                self.document = doc
                // No need for updateNSView to be called explicitly -
                // SwiftUI will call it when the @State variable changes
            }
        }
    }
}
