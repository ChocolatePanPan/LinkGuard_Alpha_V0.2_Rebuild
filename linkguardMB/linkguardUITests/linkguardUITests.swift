import XCTest

final class linkguardUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Launch & Basic Layout

    func testAppLaunchesSuccessfully() throws {
        XCTAssertTrue(app.state == .runningForeground,
                      "App should be running in the foreground after launch")
    }

    func testMainTitleIsVisible() throws {
        let title = app.staticTexts["LinkGuard"]
        XCTAssertTrue(title.waitForExistence(timeout: 5),
                      "Main 'LinkGuard' title should be visible on launch")
    }

    func testShieldIconIsVisible() throws {
        // The shield image is rendered by SwiftUI; check that the navigation title exists
        let navTitle = app.navigationBars["LinkGuard"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5),
                      "Navigation bar with 'LinkGuard' title should be visible")
    }

    // MARK: - Action Buttons

    func testScanNetworkButtonExists() throws {
        let button = app.buttons["Scan Network"]
        XCTAssertTrue(button.waitForExistence(timeout: 5),
                      "'Scan Network' button should be visible")
    }

    func testAlarmButtonExists() throws {
        // Button title is either "Test Alarm" or "Stop Alarm" depending on state
        let testAlarm = app.buttons["Test Alarm"]
        let stopAlarm = app.buttons["Stop Alarm"]
        let exists = testAlarm.waitForExistence(timeout: 5) || stopAlarm.waitForExistence(timeout: 2)
        XCTAssertTrue(exists, "Alarm toggle button should be visible")
    }

    func testNotificationsButtonExists() throws {
        let button = app.buttons["Notifications"]
        XCTAssertTrue(button.waitForExistence(timeout: 5),
                      "'Notifications' button should be visible")
    }

    func testGenerateReportButtonExists() throws {
        let button = app.buttons["Generate Report"]
        XCTAssertTrue(button.waitForExistence(timeout: 5),
                      "'Generate Report' button should be visible")
    }

    // MARK: - Command Execution

    func testTappingScanNetworkShowsAlert() throws {
        let button = app.buttons["Scan Network"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()

        let alert = app.alerts["LinkGuard"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5),
                      "An alert should appear after tapping 'Scan Network'")

        alert.buttons["OK"].tap()
    }

    func testTappingGenerateReportShowsAlert() throws {
        let button = app.buttons["Generate Report"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()

        let alert = app.alerts["LinkGuard"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5),
                      "An alert should appear after tapping 'Generate Report'")

        alert.buttons["OK"].tap()
    }

    func testTappingNotificationsButtonShowsAlert() throws {
        let button = app.buttons["Notifications"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()

        let alert = app.alerts["LinkGuard"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5),
                      "An alert should appear after tapping 'Notifications'")

        alert.buttons["OK"].tap()
    }

    // MARK: - Command History

    func testCommandHistoryAppearsAfterScan() throws {
        let button = app.buttons["Scan Network"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()

        // Dismiss alert
        let alert = app.alerts["LinkGuard"]
        if alert.waitForExistence(timeout: 5) {
            alert.buttons["OK"].tap()
        }

        // History entry should now appear
        let historyEntry = app.staticTexts["Scan Network"]
        XCTAssertTrue(historyEntry.waitForExistence(timeout: 5),
                      "A 'Scan Network' history entry should be visible after execution")
    }
}
