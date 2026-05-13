import XCTest
@testable import Litter

final class GoalSlashCommandTests: XCTestCase {
    func testBareGoalShowsCurrentGoal() {
        XCTAssertEqual(parseGoalSlashCommand(""), .show)
        XCTAssertEqual(parseGoalSlashCommand("   "), .show)
        XCTAssertEqual(parseGoalSlashCommand("status"), .show)
    }

    func testGoalObjectiveShorthandAndSetVerb() {
        XCTAssertEqual(parseGoalSlashCommand("ship the Swift toolchain"), .setObjective("ship the Swift toolchain"))
        XCTAssertEqual(parseGoalSlashCommand("set ship the Swift toolchain"), .setObjective("ship the Swift toolchain"))
        XCTAssertEqual(parseGoalSlashCommand("create debug the app"), .setObjective("debug the app"))
    }

    func testGoalStatusVerbs() {
        XCTAssertEqual(parseGoalSlashCommand("pause"), .setStatus(.paused))
        XCTAssertEqual(parseGoalSlashCommand("resume"), .setStatus(.active))
        XCTAssertEqual(parseGoalSlashCommand("complete"), .setStatus(.complete))
    }

    func testGoalBudgetParsing() {
        XCTAssertEqual(parseGoalSlashCommand("budget 50000"), .setBudget(50_000))

        guard case .usage(let message) = parseGoalSlashCommand("budget nope") else {
            return XCTFail("Expected invalid budget to return usage")
        }
        XCTAssertEqual(message, "Goal budget must be a positive token count, for example /goal budget 50000.")
    }

    func testGoalUsageMessageIncludesCreatePath() {
        let usage = goalSlashUsageMessage(prefix: "No goal is set for this thread.")

        XCTAssertTrue(usage.contains("No goal is set for this thread."))
        XCTAssertTrue(usage.contains("/goal <objective>"))
        XCTAssertTrue(usage.contains("/goal budget <tokens>"))
    }
}
