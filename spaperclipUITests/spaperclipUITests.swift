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
    func testQuietLaunchAndOpenClipboardHistory() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SPAPERCLIP_UI_TEST_ID"] = UUID().uuidString
        app.launch()

        let history = app.descendants(matching: .any)["clipboard.history"]
        XCTAssertFalse(
            history.waitForExistence(timeout: 2),
            "Expected Paperclip to launch quietly without opening Clipboard History"
        )
        let statusItem = app.statusItems["paperclip.menu-bar"]
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        statusItem.click()
        app.menuItems["Open Clipboard History"].click()
        XCTAssertTrue(
            history.waitForExistence(timeout: 5),
            "Expected the status-menu action to open Clipboard History"
        )
    }

    @MainActor
    func testCaptureSearchAndRestoreText() throws {
        let app = launchIsolatedApp()

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
        XCTAssertTrue(quickSearchRow(containing: newerValue, in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(quickSearchRow(containing: olderValue, in: app).exists)

        // Newest is selected first; Down selects the older matching result.
        field.typeKey(.downArrow, modifierFlags: [])
        NSPasteboard.general.clearContents()
        field.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), olderValue)
        dismissPermissionFallbackIfNeeded(field: field, in: app)

        // Every invocation is a fresh session with an empty query and the restored item first.
        openQuickSearch(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "")
        let quickHistory = app.descendants(matching: .any)["quick-search.history"]
        XCTAssertTrue(quickHistory.waitForExistence(timeout: 2))
        XCTAssertTrue(
            quickSearchRow(containing: olderValue, in: app).waitForExistence(timeout: 2),
            "Expected the restored item in the reopened Quick Search history"
        )
        NSPasteboard.general.clearContents()
        field.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(
            NSPasteboard.general.string(forType: .string),
            olderValue,
            "Reopening and pressing Enter should restore the promoted current item"
        )
        dismissPermissionFallbackIfNeeded(field: field, in: app)

        openQuickSearch(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let pasteboardBeforeEscape = NSPasteboard.general.string(forType: .string)
        app.typeText("does not mutate clipboard")
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(field.waitForExistence(timeout: 1))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), pasteboardBeforeEscape)
    }

    @MainActor
    func testQuickSearchDismissesWhenPanelLosesFocus() throws {
        let app = launchIsolatedApp()
        XCTAssertTrue(
            app.descendants(matching: .any)["clipboard.history"].waitForExistence(timeout: 10)
        )

        openQuickSearch(in: app)
        let field = app.textFields["quick-search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.typeText("temporary query")
        let pasteboardBeforeFocusLoss = NSPasteboard.general.string(forType: .string)

        // Activating another application causes the Quick Search panel to resign key.
        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()

        XCTAssertFalse(field.waitForExistence(timeout: 1))
        XCTAssertEqual(
            NSPasteboard.general.string(forType: .string), pasteboardBeforeFocusLoss,
            "Focus loss should dismiss without restoring a clipboard item"
        )

        // Return to Paperclip, then reopen after implicit dismissal.
        app.activate()
        openQuickSearch(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "")
        app.typeText("focused")
        XCTAssertEqual(field.value as? String, "focused")
        field.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testDetailCopyShowsFeedbackAndMarksRestoredItemCurrent() throws {
        let app = launchIsolatedApp()
        XCTAssertTrue(
            app.descendants(matching: .any)["clipboard.history"].waitForExistence(timeout: 10)
        )

        let olderValue = "Older polish \(UUID().uuidString)"
        let newerValue = "Newer polish \(UUID().uuidString)"
        capture(olderValue, in: app)
        capture(newerValue, in: app)

        let olderRowText = app.staticTexts[olderValue]
        XCTAssertTrue(olderRowText.waitForExistence(timeout: 5))
        olderRowText.click()

        let copyButton = app.buttons["clipboard.copy-all"]
        XCTAssertTrue(copyButton.waitForExistence(timeout: 5))
        copyButton.click()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), olderValue)
        let copied = NSPredicate(format: "value == %@", "Copied")
        expectation(for: copied, evaluatedWith: copyButton)
        waitForExpectations(timeout: 2)
        XCTAssertTrue(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", "current clipboard content")
            ).firstMatch.waitForExistence(timeout: 2)
        )
    }

    @MainActor
    func testClearHistoryRequiresConfirmation() throws {
        let app = launchIsolatedApp()
        XCTAssertTrue(
            app.descendants(matching: .any)["clipboard.history"].waitForExistence(timeout: 10)
        )
        let value = "Keep until confirmed \(UUID().uuidString)"
        capture(value, in: app)

        openClearHistory(in: app)
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 2))
        app.sheets.buttons["Cancel"].click()
        XCTAssertTrue(app.staticTexts[value].waitForExistence(timeout: 2))

        openClearHistory(in: app)
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 2))
        app.sheets.buttons["Clear History"].click()
        XCTAssertTrue(app.staticTexts["clipboard.empty-state"].waitForExistence(timeout: 5))
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

        let statusItem = app.statusItems["paperclip.menu-bar"]
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
        dismissPermissionFallbackIfNeeded(field: field, in: app)
    }

    @MainActor
    private func dismissPermissionFallbackIfNeeded(
        field: XCUIElement,
        in app: XCUIApplication
    ) {
        if field.waitForExistence(timeout: 1) {
            field.typeKey(.escape, modifierFlags: [])
            XCTAssertFalse(field.waitForExistence(timeout: 1))
        }
    }

    @MainActor
    private func launchIsolatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SPAPERCLIP_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        let statusItem = app.statusItems["paperclip.menu-bar"]
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        statusItem.click()
        app.menuItems["Open Clipboard History"].click()
        XCTAssertTrue(
            app.descendants(matching: .any)["clipboard.history"].waitForExistence(timeout: 5)
        )
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
    private func quickSearchRow(
        containing text: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "quick-search.history.item")
            .matching(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
    }

    @MainActor
    private func openClearHistory(in app: XCUIApplication) {
        let statusItem = app.statusItems["paperclip.menu-bar"]
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        statusItem.click()
        app.menuItems["Clear History…"].click()
    }

    @MainActor
    private func openQuickSearch(in app: XCUIApplication) {
        let statusItem = app.statusItems["paperclip.menu-bar"]
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
