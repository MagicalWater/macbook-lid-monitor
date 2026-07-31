import XCTest
@testable import LidMonitorCore

final class ProcessSignalControllerTests: XCTestCase {
    func testSecondRealSIGTERMDuringHandlerDoesNotTerminateChild() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("macbook-lid-monitor-signal-probe-\(UUID().uuidString)")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "xctest",
            "-XCTest",
            "LidMonitorTests.ProcessSignalControllerTests/testRepeatedSignalProbeChild",
            Bundle(for: Self.self).bundleURL.path
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["MLM_SIGNAL_PROBE_CHILD"] = "1"
        environment["MLM_SIGNAL_PROBE_DIRECTORY"] = directory.path
        process.environment = environment
        process.standardOutput = output
        process.standardError = output

        try process.run()
        let ready = directory.appendingPathComponent("ready")
        let entered = directory.appendingPathComponent("entered")
        let completed = directory.appendingPathComponent("completed")

        guard waitForMarker(ready) else {
            process.terminate()
            process.waitUntilExit()
            XCTFail("child did not become ready: \(childOutput(from: output))")
            return
        }
        XCTAssertEqual(kill(process.processIdentifier, SIGTERM), 0)
        guard waitForMarker(entered) else {
            process.terminate()
            process.waitUntilExit()
            XCTFail("signal handler did not start: \(childOutput(from: output))")
            return
        }

        XCTAssertEqual(kill(process.processIdentifier, SIGTERM), 0)
        process.waitUntilExit()
        let transcript = childOutput(from: output)

        XCTAssertEqual(process.terminationReason, .exit, transcript)
        XCTAssertEqual(process.terminationStatus, 0, transcript)
        XCTAssertTrue(fileManager.fileExists(atPath: completed.path), transcript)
    }

    func testRepeatedSignalProbeChild() throws {
        guard ProcessInfo.processInfo.environment["MLM_SIGNAL_PROBE_CHILD"] == "1" else {
            throw XCTSkip("signal probe child only")
        }
        let directory = try XCTUnwrap(
            ProcessInfo.processInfo.environment["MLM_SIGNAL_PROBE_DIRECTORY"]
        )
        let baseURL = URL(fileURLWithPath: directory, isDirectory: true)
        let finished = DispatchSemaphore(value: 0)
        let controller = ProcessSignalController()
        let enteredURL = baseURL.appendingPathComponent("entered")
        let completedURL = baseURL.appendingPathComponent("completed")

        try controller.start {
            try? Data().write(to: enteredURL)
            usleep(500_000)
            try? Data().write(to: completedURL)
            finished.signal()
        }
        try Data().write(to: baseURL.appendingPathComponent("ready"))
        finished.wait()
        controller.stop()
    }

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

    private func waitForMarker(_ url: URL, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            usleep(10_000)
        }
        return false
    }

    private func childOutput(from pipe: Pipe) -> String {
        String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? "<non-UTF8 child output>"
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    func increment() { lock.lock(); storage += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return storage }
}
