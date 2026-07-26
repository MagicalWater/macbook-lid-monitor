import XCTest
@testable import LidMonitorCore

final class SleepProbeApplicationTests: XCTestCase {
    func testNoArgumentsReturnsUsageWithoutOperation() {
        let fixture = ProbeFixture()
        XCTAssertEqual(fixture.run([]), ExitCode.usage.rawValue)
        XCTAssertEqual(fixture.operation.callCount, 0)
    }

    func testDryRunReportsWouldRequestWithoutOperation() {
        let fixture = ProbeFixture()
        XCTAssertEqual(fixture.run(["--dry-run"]), ExitCode.success.rawValue)
        XCTAssertEqual(fixture.operation.callCount, 0)
        XCTAssertEqual(fixture.lines, ["sleep-probe: would-request-sleep"])
    }

    func testExecuteRequiresExactApprovalToken() {
        let fixture = ProbeFixture()
        XCTAssertEqual(fixture.run(["--execute-once"]), ExitCode.usage.rawValue)
        XCTAssertEqual(fixture.run(["--execute-once", "--approval-token", "WRONG"]), ExitCode.usage.rawValue)
        XCTAssertEqual(fixture.operation.callCount, 0)
    }

    func testExactExecuteCommandCallsOperationOnce() {
        let fixture = ProbeFixture()
        XCTAssertEqual(
            fixture.run(["--execute-once", "--approval-token", SleepProbeApplication.approvalToken]),
            ExitCode.success.rawValue
        )
        XCTAssertEqual(fixture.operation.callCount, 1)
        XCTAssertEqual(fixture.lines, ["sleep-probe: sleep-requested"])
    }

    func testOperationFailureIsStableAndNotRetried() {
        let fixture = ProbeFixture()
        fixture.operation.error = IOKitSystemSleepError.requestFailed(-1)
        XCTAssertEqual(
            fixture.run(["--execute-once", "--approval-token", SleepProbeApplication.approvalToken]),
            ExitCode.internalError.rawValue
        )
        XCTAssertEqual(fixture.operation.callCount, 1)
        XCTAssertEqual(fixture.lines, ["sleep-probe: sleep-request-failed error=iokit-request-failed(-1)"])
    }

    func testExtraArgumentsReturnUsageWithoutOperation() {
        let fixture = ProbeFixture()
        XCTAssertEqual(fixture.run(["--dry-run", "extra"]), ExitCode.usage.rawValue)
        XCTAssertEqual(fixture.operation.callCount, 0)
    }
}

private final class ProbeFixture {
    let operation = ProbeOperation()
    private let output = ProbeOutput()
    var lines: [String] { output.lines }

    func run(_ arguments: [String]) -> Int32 {
        SleepProbeApplication(operation: operation, output: { [output] in output.append($0) })
            .run(arguments: arguments)
    }
}

private final class ProbeOperation: SystemSleepOperating, @unchecked Sendable {
    var callCount = 0
    var error: Error?
    func requestSleep() throws {
        callCount += 1
        if let error { throw error }
    }
}

private final class ProbeOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    func append(_ line: String) { lock.lock(); storage.append(line); lock.unlock() }
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return storage }
}
