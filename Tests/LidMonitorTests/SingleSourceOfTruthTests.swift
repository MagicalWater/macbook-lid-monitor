import Foundation
import XCTest
@testable import LidMonitorCore

final class SingleSourceOfTruthTests: XCTestCase {
    func testDryRunHelperDoesNotDuplicatePolicyValues() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = projectRoot
            .appendingPathComponent("scripts")
            .appendingPathComponent("run-auto-sleep-dry-run.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertFalse(script.contains("--sleep-threshold"))
        XCTAssertFalse(script.contains("--reopen-threshold"))
        XCTAssertFalse(script.contains("--debounce"))
        XCTAssertFalse(script.contains("--wake-cooldown"))
        XCTAssertFalse(script.contains("--startup-cooldown"))
        XCTAssertFalse(script.contains("--wake-recovery"))
    }
}
