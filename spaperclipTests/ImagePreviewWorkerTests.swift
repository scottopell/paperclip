import AppKit
import PDFKit
import XCTest
@testable import spaperclip

final class ImagePreviewWorkerTests: XCTestCase {
    private func imageData() -> Data {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        return bitmap.representation(using: .png, properties: [:])!
    }

    func testRapidSelectionsOnlyDeliverLatestDocument() {
        let worker = ImagePreviewWorker()
        let latest = expectation(description: "latest image is delivered")
        let data = imageData()
        var delivered = [UUID]()
        for _ in 0..<100 {
            _ = worker.load(data: data) { ticket, _ in delivered.append(ticket) }
        }
        let ticket = worker.load(data: data) { result, document in
            delivered.append(result)
            XCTAssertEqual(document?.pageCount, 1)
            latest.fulfill()
        }
        wait(for: [latest], timeout: 5)
        XCTAssertEqual(delivered, [ticket])
    }

    func testSeparateViewsDoNotCancelEachOthersImages() {
        let first = ImagePreviewWorker()
        let second = ImagePreviewWorker()
        let both = expectation(description: "both view-owned decoders complete")
        both.expectedFulfillmentCount = 2
        let data = imageData()
        _ = first.load(data: data) { _, document in
            XCTAssertEqual(document?.pageCount, 1)
            both.fulfill()
        }
        _ = second.load(data: data) { _, document in
            XCTAssertEqual(document?.pageCount, 1)
            both.fulfill()
        }
        wait(for: [both], timeout: 5)
    }

    func testCancelDropsPendingResultAndAllowsNextSelection() {
        let worker = ImagePreviewWorker()
        let cancelled = expectation(description: "cancelled image must not deliver")
        cancelled.isInverted = true
        let old = worker.load(data: imageData()) { _, _ in cancelled.fulfill() }
        worker.cancel(old)

        let current = expectation(description: "replacement delivered")
        _ = worker.load(data: Data("not an image".utf8)) { _, document in
            XCTAssertNil(document)
            current.fulfill()
        }
        wait(for: [current, cancelled], timeout: 1)
    }
}
