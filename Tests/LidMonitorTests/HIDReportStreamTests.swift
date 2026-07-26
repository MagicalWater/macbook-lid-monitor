import Foundation
import XCTest
@testable import LidMonitorCore

final class HIDReportStreamTests: XCTestCase {
    func testStartOpensRegistersAndRunsSession() throws {
        let session = FakeHIDDeviceSession()
        let stream = IOHIDReportStream(session: session, runAsynchronously: false)

        try stream.start { _ in }

        XCTAssertEqual(session.openCount, 1)
        XCTAssertEqual(session.registerCount, 1)
        XCTAssertEqual(session.runCount, 1)
    }

    func testStopIsIdempotentAndClosesOnce() throws {
        let session = FakeHIDDeviceSession()
        let stream = IOHIDReportStream(session: session, runAsynchronously: false)
        try stream.start { _ in }

        stream.stop()
        stream.stop()

        XCTAssertEqual(session.stopCount, 1)
        XCTAssertEqual(session.closeCount, 1)
    }

    func testCallbackCopiesReportIntoTypedValue() throws {
        let session = FakeHIDDeviceSession()
        let stream = IOHIDReportStream(session: session, runAsynchronously: false)
        let captured = ReportBox()

        try stream.start { captured.value = $0 }
        session.callback?(7, [1, 2, 3])

        XCTAssertEqual(captured.value?.reportID, 7)
        XCTAssertEqual(captured.value?.bytes, [1, 2, 3])
    }
}

private final class ReportBox: @unchecked Sendable {
    var value: HIDReport?
}

private final class FakeHIDDeviceSession: HIDDeviceSession, @unchecked Sendable {
    var openCount = 0
    var registerCount = 0
    var runCount = 0
    var stopCount = 0
    var closeCount = 0
    var callback: (@Sendable (UInt32, [UInt8]) -> Void)?

    func open() throws { openCount += 1 }

    func registerInputCallback(
        _ callback: @escaping @Sendable (UInt32, [UInt8]) -> Void
    ) throws {
        registerCount += 1
        self.callback = callback
    }

    func run() { runCount += 1 }
    func stop() { stopCount += 1 }
    func close() { closeCount += 1 }
}
