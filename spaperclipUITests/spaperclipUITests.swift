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
    func testQuickSearchKeyboardJourney() throws {
        let app = launchIsolatedApp()
        let mainHistory = app.descendants(matching: .any)["clipboard.history"]
        XCTAssertTrue(mainHistory.waitForExistence(timeout: 10))

        let uniqueToken = String(UUID().uuidString.prefix(8))
        let sharedPrefix = "Quick option \(uniqueToken)"
        let olderValue = "\(sharedPrefix) older"
        let newerValue = "\(sharedPrefix) newer"
        capture(olderValue, in: app)
        capture(newerValue, in: app)

        let closeButtonCount = app.buttons.matching(identifier: "_XCUI:CloseWindow").count
        let minimizeButtonCount = app.buttons.matching(identifier: "_XCUI:MinimizeWindow").count
        let zoomButtonCount = app.buttons.matching(identifier: "_XCUI:ZoomWindow").count

        openQuickSearch(in: app)
        let field = app.textFields["quick-search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))

        // Type through the application, without clicking the field, to prove first-responder focus.
        XCTAssertEqual(app.buttons.matching(identifier: "_XCUI:CloseWindow").count, closeButtonCount)
        XCTAssertEqual(
            app.buttons.matching(identifier: "_XCUI:MinimizeWindow").count,
            minimizeButtonCount
        )
        XCTAssertEqual(app.buttons.matching(identifier: "_XCUI:ZoomWindow").count, zoomButtonCount)

        let fuzzyQuery = "qo\(uniqueToken)"
        app.typeText(fuzzyQuery)
        XCTAssertEqual(field.value as? String, fuzzyQuery)
        XCTAssertTrue(app.staticTexts[newerValue].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts[olderValue].exists)

        // Newest is selected first; Down selects the older matching result.
        field.typeKey(.downArrow, modifierFlags: [])
        NSPasteboard.general.clearContents()
        field.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), olderValue)
        XCTAssertFalse(field.waitForExistence(timeout: 1))

        // Every invocation is a fresh session with an empty query and the restored item first.
        openQuickSearch(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "")
        let quickHistory = app.descendants(matching: .any)["quick-search.history"]
        XCTAssertTrue(quickHistory.waitForExistence(timeout: 2))
        XCTAssertTrue(
            quickHistory.staticTexts[olderValue].waitForExistence(timeout: 2),
            "Expected the restored item in the reopened Quick Search history"
        )
        NSPasteboard.general.clearContents()
        field.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(
            NSPasteboard.general.string(forType: .string),
            olderValue,
            "Reopening and pressing Enter should restore the promoted current item"
        )
        XCTAssertFalse(field.waitForExistence(timeout: 1))

        openQuickSearch(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let pasteboardBeforeEscape = NSPasteboard.general.string(forType: .string)
        app.typeText("does not mutate clipboard")
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(field.waitForExistence(timeout: 1))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), pasteboardBeforeEscape)
    }

    @MainActor
    func testDatabaseStatisticsRefreshesOnItsCoreDataQueue() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "-com.apple.CoreData.ConcurrencyDebug", "1",
        ]
        app.launchEnvironment["SPAPERCLIP_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        app.activate()

        XCTAssertTrue(
            app.descendants(matching: .any)["clipboard.history"].waitForExistence(timeout: 10)
        )

        let statusItem = app.statusItems["stats.menu-bar"]
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        statusItem.click()
        app.menuItems["Database Statistics"].click()

        let stats = app.descendants(matching: .any)["stats.root"]
        XCTAssertTrue(stats.waitForExistence(timeout: 5))
        let refresh = app.buttons["Refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Core Data Statistics"].exists)

        for _ in 0..<5 {
            XCTAssertTrue(refresh.waitForExistence(timeout: 5))
            if refresh.isEnabled { refresh.click() }
        }

        XCTAssertTrue(stats.exists)

        XCTAssertTrue(app.windows["Database Statistics"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Core Data Statistics"].exists)
    }

    @MainActor
    func testShortcutIsConfigurableInSettings() throws {
        let app = launchIsolatedApp()
        XCTAssertTrue(
            app.descendants(matching: .any)["clipboard.history"].waitForExistence(timeout: 10)
        )

        app.typeKey(",", modifierFlags: [.command])
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.shortcuts"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.quick-search-shortcut"]
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testQuickSearchPlainTextRestore() throws {
        let app = launchIsolatedApp()
        XCTAssertTrue(
            app.descendants(matching: .any)["clipboard.history"].waitForExistence(timeout: 10)
        )

        let value = "Quick shortcut \(UUID().uuidString)"
        capture(value, in: app)

        openQuickSearch(in: app)
        let field = app.textFields["quick-search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.typeText("Quick shortcut")
        XCTAssertTrue(app.staticTexts[value].waitForExistence(timeout: 2))

        NSPasteboard.general.clearContents()
        field.typeKey(.return, modifierFlags: [.shift])
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), value)
        XCTAssertFalse(field.waitForExistence(timeout: 1))
    }

    @MainActor
    private func launchIsolatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SPAPERCLIP_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        app.activate()
        return app
    }

    @MainActor
    private func capture(_ text: String, in app: XCUIApplication) {
        NSPasteboard.general.clearContents()
        XCTAssertTrue(NSPasteboard.general.setString(text, forType: .string))
        XCTAssertTrue(
            app.staticTexts[text].waitForExistence(timeout: 5),
            "Expected clipboard monitor to capture \(text)"
        )
    }

    @MainActor
    private func openQuickSearch(in app: XCUIApplication) {
        let statusItem = app.statusItems["stats.menu-bar"]
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        statusItem.click()
        app.menuItems["Quick Search"].click()
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
