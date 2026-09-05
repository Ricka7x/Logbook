import XCTest

@testable import Logbook

final class LogbookTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var logger: Logbook!

    override func setUp() {
        super.setUp()
        suiteName = "Logbook.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        logger = Logbook(defaults: defaults, subsystem: "test")
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        logger = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsToEnabledWithDebugMinimumLevel() {
        // Package always builds this test target in debug, so both defaults apply here
        // regardless of the host app's own build configuration.
        XCTAssertTrue(logger.isEnabled)
        XCTAssertEqual(logger.minimumLevel, .debug)
    }

    func testSettingsPersistAcrossInstancesSharingTheSameSuite() {
        logger.isEnabled = false
        logger.minimumLevel = .error

        let second = Logbook(defaults: defaults, subsystem: "test")

        XCTAssertFalse(second.isEnabled)
        XCTAssertEqual(second.minimumLevel, .error)
    }

    func testWillLogRespectsGlobalEnabledFlag() {
        logger.isEnabled = false
        XCTAssertFalse(logger.willLog(level: .error, category: .general))
    }

    func testWillLogRespectsMinimumLevel() {
        logger.minimumLevel = .warning
        XCTAssertFalse(logger.willLog(level: .info, category: .general))
        XCTAssertTrue(logger.willLog(level: .warning, category: .general))
        XCTAssertTrue(logger.willLog(level: .error, category: .general))
    }

    func testCategoriesAreEnabledByDefault() {
        let custom = LogCategory("custom")
        XCTAssertTrue(logger.isCategoryEnabled(custom))
        XCTAssertTrue(logger.willLog(level: .debug, category: custom))
    }

    func testDisablingACategoryStopsItFromLogging() {
        let custom = LogCategory("custom")
        logger.disable(custom)

        XCTAssertFalse(logger.isCategoryEnabled(custom))
        XCTAssertFalse(logger.willLog(level: .error, category: custom))
        // Unrelated categories are unaffected.
        XCTAssertTrue(logger.willLog(level: .debug, category: .general))
    }

    func testEnableAllCategoriesClearsEveryDisabledCategory() {
        let a = LogCategory("a")
        let b = LogCategory("b")
        logger.disable(a)
        logger.disable(b)

        logger.enableAllCategories()

        XCTAssertTrue(logger.isCategoryEnabled(a))
        XCTAssertTrue(logger.isCategoryEnabled(b))
    }

    func testMessageAutoclosureIsNotEvaluatedWhenFilteredOut() {
        logger.minimumLevel = .error
        var evaluated = false

        logger.debug(
            {
                evaluated = true
                return "expensive"
            }(), service: "Test")

        XCTAssertFalse(evaluated)
    }

    func testRecentLogsCapturesEmittedEntries() {
        logger.error("boom", service: "Test", category: .general)

        let lines = logger.recentLogs(minimumLevel: .debug, limit: 10)

        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("boom"))
        XCTAssertTrue(lines[0].contains("Test"))
    }

    func testRecentLogsFiltersByMinimumLevel() {
        logger.debug("low", service: "Test")
        logger.error("high", service: "Test")

        let lines = logger.recentLogs(minimumLevel: .error, limit: 10)

        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("high"))
    }

    func testRecentLogsFiltersByService() {
        logger.error("from A", service: "A")
        logger.error("from B", service: "B")

        let lines = logger.recentLogs(minimumLevel: .debug, service: "A", limit: 10)

        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("from A"))
    }

    func testRecentLogsFiltersBySearchTerm() {
        logger.error("network timeout", service: "Test")
        logger.error("disk full", service: "Test")

        let lines = logger.recentLogs(minimumLevel: .debug, search: "timeout", limit: 10)

        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("network timeout"))
    }

    func testRecentLogsRespectsRingBufferLimit() {
        let small = Logbook(defaults: defaults, subsystem: "small-buffer", maxRecentEntries: 3)
        for i in 0..<10 {
            small.error("entry \(i)", service: "Test")
        }

        let lines = small.recentLogs(minimumLevel: .debug, limit: 100)

        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines.last!.contains("entry 9"))
    }

    func testSuppressedLogDoesNotAppearInRecentLogs() {
        logger.disable(.general)
        logger.error("should not appear", service: "Test", category: .general)

        let lines = logger.recentLogs(minimumLevel: .debug, limit: 10)

        XCTAssertTrue(lines.isEmpty)
    }
}
