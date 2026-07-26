import XCTest
import IOKit
import IOKit.pwr_mgt
@testable import LidMonitorCore

final class IOKitSystemPowerObserverTests: XCTestCase {
    func testCanSleepIsAcknowledgedBeforeForwarding() throws {
        let operation = FakeSystemPowerNotificationOperation()
        let observer = IOKitSystemPowerObserver(operation: operation, now: { Date(timeIntervalSince1970: 1) })
        let events = LockedValues<SystemPowerEvent>()
        try observer.start { event, _ in
            events.append(event)
            operation.sequence.append("event")
        }

        operation.emit(SystemPowerMessage.canSystemSleep, notificationID: 41)

        XCTAssertEqual(events.values, [.canSleep])
        XCTAssertEqual(operation.allowedNotificationIDs, [41])
        XCTAssertEqual(operation.sequence, ["allow", "event"])
    }

    func testWillSleepIsAcknowledgedBeforeForwarding() throws {
        let operation = FakeSystemPowerNotificationOperation()
        let observer = IOKitSystemPowerObserver(operation: operation)
        let events = LockedValues<SystemPowerEvent>()
        try observer.start { event, _ in events.append(event) }

        operation.emit(SystemPowerMessage.systemWillSleep, notificationID: 42)

        XCTAssertEqual(events.values, [.willSleep])
        XCTAssertEqual(operation.allowedNotificationIDs, [42])
    }

    func testPowerOnMessagesMapExactlyAndUnknownIsIgnored() throws {
        let operation = FakeSystemPowerNotificationOperation()
        let observer = IOKitSystemPowerObserver(operation: operation)
        let events = LockedValues<SystemPowerEvent>()
        try observer.start { event, _ in events.append(event) }

        operation.emit(SystemPowerMessage.systemWillPowerOn, notificationID: 1)
        operation.emit(SystemPowerMessage.systemHasPoweredOn, notificationID: 2)
        operation.emit(0xDEADBEEF, notificationID: 3)

        XCTAssertEqual(events.values, [.willPowerOn, .hasPoweredOn])
        XCTAssertTrue(operation.allowedNotificationIDs.isEmpty)
    }

    func testStartAndStopAreIdempotent() throws {
        let operation = FakeSystemPowerNotificationOperation()
        let observer = IOKitSystemPowerObserver(operation: operation)
        try observer.start { _, _ in }
        try observer.start { _, _ in }
        observer.stop()
        observer.stop()

        XCTAssertEqual(operation.registerCount, 1)
        XCTAssertEqual(operation.deregisterCount, 1)
    }

    func testRegistrationFailureLeavesNoActiveRegistration() {
        let operation = FakeSystemPowerNotificationOperation()
        operation.registrationError = TestPowerError.registration
        let observer = IOKitSystemPowerObserver(operation: operation)

        XCTAssertThrowsError(try observer.start { _, _ in })
        observer.stop()

        XCTAssertEqual(operation.registerCount, 1)
        XCTAssertEqual(operation.deregisterCount, 0)
    }

    func testDeinitCleansUpOnce() throws {
        let operation = FakeSystemPowerNotificationOperation()
        var observer: IOKitSystemPowerObserver? = IOKitSystemPowerObserver(operation: operation)
        try observer?.start { _, _ in }
        observer = nil

        XCTAssertEqual(operation.deregisterCount, 1)
    }

    func testWakeAdapterForwardsOnlyHasPoweredOn() throws {
        let operation = FakeSystemPowerNotificationOperation()
        let powerObserver = IOKitSystemPowerObserver(operation: operation)
        let wakeObserver = IOKitSystemWakeObserver(powerObserver: powerObserver)
        let wakes = LockedValues<Date>()
        try wakeObserver.start { wakes.append($0) }

        operation.emit(SystemPowerMessage.systemWillPowerOn, notificationID: 1)
        operation.emit(SystemPowerMessage.systemHasPoweredOn, notificationID: 2)

        XCTAssertEqual(wakes.values.count, 1)
        wakeObserver.stop()
    }
}


private final class LockedValues<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    func append(_ value: Value) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private enum TestPowerError: Error {
    case registration
}

private final class FakeSystemPowerNotificationOperation: SystemPowerNotificationOperating, @unchecked Sendable {
    var callback: (@Sendable (UInt32, Int) -> Void)?
    var registrationError: Error?
    var registerCount = 0
    var deregisterCount = 0
    var allowedNotificationIDs: [Int] = []
    var sequence: [String] = []

    func register(callback: @escaping @Sendable (UInt32, Int) -> Void) throws -> SystemPowerRegistration {
        registerCount += 1
        if let registrationError { throw registrationError }
        self.callback = callback
        return SystemPowerRegistration(rootPort: 99)
    }

    func allowPowerChange(rootPort: io_connect_t, notificationID: Int) {
        XCTAssertEqual(rootPort, 99)
        allowedNotificationIDs.append(notificationID)
        sequence.append("allow")
    }

    func deregister(_ registration: SystemPowerRegistration) {
        deregisterCount += 1
        callback = nil
    }

    func emit(_ message: UInt32, notificationID: Int) {
        callback?(message, notificationID)
    }
}
