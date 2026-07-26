import Foundation
import XCTest
@testable import LidMonitorCore

final class CrashBudgetTests: XCTestCase {
    func testUnexpectedExitsOpenCircuitWithinRollingWindow() throws {
        let storage = MemoryCrashBudgetStorage()
        var budget = CrashBudget(storage: storage, maximumUnexpectedExits: 3, window: 300)
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertFalse(try budget.recordUnexpectedExit(at: start).isCircuitOpen)
        XCTAssertFalse(try budget.recordUnexpectedExit(at: start.addingTimeInterval(10)).isCircuitOpen)
        XCTAssertTrue(try budget.recordUnexpectedExit(at: start.addingTimeInterval(20)).isCircuitOpen)
        XCTAssertFalse(try budget.allowsStart(at: start.addingTimeInterval(21)))
    }

    func testRollingWindowDropsOldUnexpectedExits() throws {
        let storage = MemoryCrashBudgetStorage()
        var budget = CrashBudget(storage: storage, maximumUnexpectedExits: 2, window: 10)
        let start = Date(timeIntervalSince1970: 1_000)

        _ = try budget.recordUnexpectedExit(at: start)
        let result = try budget.recordUnexpectedExit(at: start.addingTimeInterval(11))

        XCTAssertFalse(result.isCircuitOpen)
        XCTAssertEqual(result.unexpectedExitCount, 1)
    }

    func testCleanExitDoesNotConsumeBudgetAndResetClearsCircuit() throws {
        let storage = MemoryCrashBudgetStorage()
        var budget = CrashBudget(storage: storage, maximumUnexpectedExits: 1, window: 300)
        let date = Date(timeIntervalSince1970: 1_000)

        try budget.recordCleanExit()
        XCTAssertTrue(try budget.allowsStart(at: date))
        _ = try budget.recordUnexpectedExit(at: date)
        XCTAssertFalse(try budget.allowsStart(at: date))

        try budget.reset()
        XCTAssertTrue(try budget.allowsStart(at: date))
    }

    func testCorruptStateFailsOpenAndDoesNotRewriteState() throws {
        let storage = MemoryCrashBudgetStorage(data: Data("not-json".utf8))
        var budget = CrashBudget(storage: storage, maximumUnexpectedExits: 3, window: 300)

        XCTAssertFalse(try budget.allowsStart(at: Date()))
        XCTAssertEqual(storage.storeCount, 0)
    }

    func testUnexpectedExitUsesAtomicStorage() throws {
        let storage = MemoryCrashBudgetStorage()
        var budget = CrashBudget(storage: storage, maximumUnexpectedExits: 3, window: 300)

        _ = try budget.recordUnexpectedExit(at: Date())

        XCTAssertEqual(storage.storeCount, 1)
    }
}

private final class MemoryCrashBudgetStorage: CrashBudgetStoring, @unchecked Sendable {
    private var data: Data?
    private(set) var storeCount = 0

    init(data: Data? = nil) { self.data = data }

    func load() throws -> Data? { data }
    func storeAtomically(_ data: Data) throws { self.data = data; storeCount += 1 }
    func remove() throws { data = nil }
}
