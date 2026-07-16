//
//  spaperclipUITests.swift
//  spaperclipUITests
//
//  Created by Scott Opell on 5/3/25.
//

import AppKit
import XCTest

final class spaperclipUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testLaunchShowsEmptyClipboardHistory() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SPAPERCLIP_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        app.activate()

        XCTAssertTrue(
            app.descendants(matching: .any)["clipboard.history"].waitForExistence(timeout: 10),
            "Expected the clipboard history surface to appear after launch"
        )
        XCTAssertTrue(
            app.staticTexts["clipboard.empty-state"].waitForExistence(timeout: 5),
            "Expected a fresh UI-test store to start with empty history"
        )
    }

    @MainActor
    func testCaptureSearchAndRestoreText() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SPAPERCLIP_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        app.activate()

        let history = app.descendants(matching: .any)["clipboard.history"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))

        let capturedText = "XCUITest clipboard \(UUID().uuidString)"
        NSPasteboard.general.clearContents()
        XCTAssertTrue(NSPasteboard.general.setString(capturedText, forType: .string))

        let capturedRow = app.staticTexts[capturedText]
        XCTAssertTrue(
            capturedRow.waitForExistence(timeout: 5),
            "Expected clipboard polling to add the copied text to history"
        )

        let searchField = app.searchFields["clipboard.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.click()
        searchField.typeText("XCUITest clipboard")
        XCTAssertTrue(capturedRow.waitForExistence(timeout: 2))

        NSPasteboard.general.clearContents()
        searchField.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(
            NSPasteboard.general.string(forType: .string),
            capturedText,
            "Enter should restore the selected history item to the pasteboard"
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
