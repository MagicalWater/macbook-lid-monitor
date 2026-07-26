import XCTest
@testable import LidMonitorCore

final class ProcessSignalControllerTests: XCTestCase {
    func testFinishForTestingInvokesStopOnce() throws {
        let controller = ProcessSignalController()
        let stopCount = LockedCounter()
        try controller.start { stopCount.increment() }

        controller.finishForTesting()
        controller.finishForTesting()

        XCTAssertEqual(stopCount.value, 1)
        controller.stop()
    }

    func testStopBeforeSignalDoesNotInvokeHandler() throws {
        let controller = ProcessSignalController()
        let stopCount = LockedCounter()
        try controller.start { stopCount.increment() }
        controller.stop()
        controller.finishForTesting()
        XCTAssertEqual(stopCount.value, 0)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    func increment() { lock.lock(); storage += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return storage }
}
