import XCTest
@testable import LidMonitorCore

final class SleepRequesterTests: XCTestCase {
    func testDryRunReportsWouldSleepWithoutCallingSystemOperation() throws {
        let operation = SpySystemSleepOperation()
        let recorder = EventRecorder()
        let requester = DryRunSleepRequester(onEvent: recorder.record)

        try requester.requestSleep()

        XCTAssertEqual(recorder.events, [.wouldSleep])
        XCTAssertEqual(operation.requestCount, 0)
    }

    func testMacOSRequesterDelegatesExactlyOnce() throws {
        let operation = SpySystemSleepOperation()
        let requester = MacOSSleepRequester(operation: operation)

        try requester.requestSleep()

        XCTAssertEqual(operation.requestCount, 1)
    }

    func testMacOSRequesterPropagatesFailureWithoutRetry() {
        let operation = SpySystemSleepOperation(error: TestError.failed)
        let requester = MacOSSleepRequester(operation: operation)

        XCTAssertThrowsError(try requester.requestSleep()) { error in
            XCTAssertEqual(error as? TestError, .failed)
        }
        XCTAssertEqual(operation.requestCount, 1)
    }

    func testIOKitFailureDescriptionsAreStable() {
        XCTAssertEqual(
            String(describing: IOKitSystemSleepError.powerManagementUnavailable),
            "power-management-unavailable"
        )
        XCTAssertEqual(
            String(describing: IOKitSystemSleepError.requestFailed(-536_870_212)),
            "iokit-request-failed(-536870212)"
        )
    }
}

private enum TestError: Error, Equatable {
    case failed
}

private final class SpySystemSleepOperation: SystemSleepOperating, @unchecked Sendable {
    private let error: Error?
    private(set) var requestCount = 0

    init(error: Error? = nil) {
        self.error = error
    }

    func requestSleep() throws {
        requestCount += 1
        if let error {
            throw error
        }
    }
}

private final class EventRecorder: @unchecked Sendable {
    private(set) var events: [AutoSleepOperationalEvent] = []

    func record(_ event: AutoSleepOperationalEvent) {
        events.append(event)
    }
}
