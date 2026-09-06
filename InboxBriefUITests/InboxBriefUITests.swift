//
//  InboxBriefUITests.swift
//  InboxBriefUITests
//
//  Created by Tin Pham on 5/9/26.
//

import XCTest

final class InboxBriefUITests: XCTestCase {

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
    func testInitialTriageAndAccountNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["Inbox Brief"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Check inboxes"].exists)

        app.buttons["Accounts"].tap()

        XCTAssertTrue(app.navigationBars["Accounts"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Add Gmail account"].exists)
    }

    @MainActor
    func testCheckInboxesShowsMissingAccountState() throws {
        let app = XCUIApplication()
        app.launch()

        let checkButton = app.buttons["Check inboxes"]
        XCTAssertTrue(checkButton.waitForExistence(timeout: 3))
        checkButton.tap()

        XCTAssertTrue(app.staticTexts["Connect a Gmail account"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Manage accounts"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
