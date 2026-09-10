//
//  InboxBriefUITests.swift
//  InboxBriefUITests
//
//  Created by Tin Pham on 5/9/26.
//

import XCTest

final class InboxBriefUITests: XCTestCase {
    private let uiTimeout: TimeInterval = 2

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
    func testLaunchWithoutAccountsShowsAccountSetup() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["Inbox Brief"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.staticTexts["Connect a Gmail account"].exists)
        let manageAccounts = app.buttons["Manage accounts"]
        XCTAssertTrue(manageAccounts.exists)

        manageAccounts.tap()

        XCTAssertTrue(app.navigationBars["Accounts"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.buttons["Add Gmail account"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
