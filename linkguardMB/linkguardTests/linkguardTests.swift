import XCTest
@testable import linkguard

final class linkguardTests: XCTestCase {

    // MARK: - AlarmPlayer Tests

    func testAlarmPlayerSingleton() {
        let player1 = AlarmPlayer.shared
        let player2 = AlarmPlayer.shared
        XCTAssertTrue(player1 === player2, "AlarmPlayer should be a singleton")
    }

    func testAlarmPlayerInitiallyNotPlaying() {
        XCTAssertFalse(AlarmPlayer.shared.isPlaying, "Alarm should not be playing on init")
    }

    func testAlarmPlayerStopWhenNotPlaying() {
        // Should not crash when stopping an alarm that isn't playing
        AlarmPlayer.shared.stopAlarm()
        XCTAssertFalse(AlarmPlayer.shared.isPlaying)
    }

    // MARK: - CommandEngine Tests

    func testCommandEngineSingleton() {
        let engine1 = CommandEngine.shared
        let engine2 = CommandEngine.shared
        XCTAssertTrue(engine1 === engine2, "CommandEngine should be a singleton")
    }

    func testScanNetworkCommand() {
        let engine = CommandEngine.shared
        let command = Command(type: .scanNetwork)
        let expectation = expectation(description: "Scan network completes")

        engine.execute(command) { result in
            XCTAssertTrue(result.success, "Scan network should succeed")
            XCTAssertFalse(result.message.isEmpty, "Result message should not be empty")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func testBlockURLWithValidURL() {
        let engine = CommandEngine.shared
        let command = Command(type: .blockURL, parameters: ["url": "http://malicious.example.com"])
        let expectation = expectation(description: "Block URL completes")

        engine.execute(command) { result in
            XCTAssertTrue(result.success)
            XCTAssertTrue(result.message.contains("malicious.example.com"))
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func testBlockURLWithMissingURL() {
        let engine = CommandEngine.shared
        let command = Command(type: .blockURL)
        let expectation = expectation(description: "Block URL fails without URL")

        engine.execute(command) { result in
            XCTAssertFalse(result.success)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func testAllowURLWithValidURL() {
        let engine = CommandEngine.shared
        let command = Command(type: .allowURL, parameters: ["url": "http://safe.example.com"])
        let expectation = expectation(description: "Allow URL completes")

        engine.execute(command) { result in
            XCTAssertTrue(result.success)
            XCTAssertTrue(result.message.contains("safe.example.com"))
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func testClearLogCommand() {
        let engine = CommandEngine.shared
        let command = Command(type: .clearLog)
        let expectation = expectation(description: "Clear log completes")

        engine.execute(command) { result in
            XCTAssertTrue(result.success)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func testGenerateReportCommand() {
        let engine = CommandEngine.shared
        let command = Command(type: .generateReport)
        let expectation = expectation(description: "Generate report completes")

        engine.execute(command) { result in
            XCTAssertTrue(result.success)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    // MARK: - NotificationManager Tests

    func testNotificationManagerSingleton() {
        let manager1 = NotificationManager.shared
        let manager2 = NotificationManager.shared
        XCTAssertTrue(manager1 === manager2, "NotificationManager should be a singleton")
    }

    func testScheduleNotificationReturnsIdentifier() {
        let manager = NotificationManager.shared
        let id = manager.scheduleNotification(title: "Test", body: "Test body")
        XCTAssertFalse(id.isEmpty, "scheduleNotification should return a non-empty identifier")
    }

    func testCancelNotificationDoesNotCrash() {
        let manager = NotificationManager.shared
        manager.cancelNotification(identifier: "non-existent-id")
        // Should not throw or crash
    }

    func testCancelAllNotificationsDoesNotCrash() {
        let manager = NotificationManager.shared
        manager.cancelAllNotifications()
        // Should not throw or crash
    }

    // MARK: - CommandType Tests

    func testAllCommandTypesHaveDisplayNames() {
        for type in CommandType.allCases {
            XCTAssertFalse(type.displayName.isEmpty,
                           "\(type.rawValue) should have a non-empty display name")
        }
    }

    func testCommandTypeIdentifiable() {
        for type in CommandType.allCases {
            XCTAssertEqual(type.id, type.rawValue)
        }
    }
}
