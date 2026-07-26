import XCTest
@testable import LidMonitorCore

final class DaemonSpikeEvidenceTests: XCTestCase {
    func testStableFirstReportLine() {
        let formatter = DaemonSpikeEvidenceFormatter(
            timestampFormatter: { _ in "2026-07-26T21:30:00+08:00" },
            pid: 123
        )
        XCTAssertEqual(
            formatter.line(for: .firstValidReport(angle: 172, count: 1), at: Date()),
            "timestamp=2026-07-26T21:30:00+08:00 event=first-valid-report pid=123 angle=172 count=1"
        )
    }

    func testRuntimeAndCandidateLinesContainIdentityAndHIDFields() {
        let formatter = DaemonSpikeEvidenceFormatter(timestampFormatter: { _ in "t" }, pid: 9)
        let identity = RuntimeIdentity(pid: 9, uid: 0, gid: 0, architecture: "arm64", operatingSystemVersion: "26.5.2")
        XCTAssertEqual(
            formatter.line(for: .runtimeStarted(identity), at: Date()),
            "timestamp=t event=runtime-started pid=9 uid=0 gid=0 architecture=arm64 macos=26.5.2"
        )
        let descriptor = HIDDeviceDescriptor(
            registryEntryID: 77, name: "Apple", vendorID: 0x05AC, productID: 0x8104,
            usagePage: 0x20, usage: 0x8A, transport: "SPU", inputClass: .other
        )
        XCTAssertEqual(
            formatter.line(for: .candidateSelected(descriptor, score: 45), at: Date()),
            "timestamp=t event=candidate-selected pid=9 registryID=77 score=45 vendorID=0x05AC productID=0x8104 usagePage=0x0020 usage=0x008A transport=SPU"
        )
    }

    func testReportRecorderEmitsOnlyFirstAndHundredMilestones() {
        let sink = RecordingEvidenceSink()
        let recorder = DaemonSpikeReportRecorder(sink: sink)
        for _ in 1...200 { recorder.record(angle: 172) }
        XCTAssertEqual(sink.events, [
            .firstValidReport(angle: 172, count: 1),
            .reportMilestone(angle: 172, count: 100),
            .reportMilestone(angle: 172, count: 200)
        ])
    }

    func testPowerAndStoppingHaveStableNames() {
        let formatter = DaemonSpikeEvidenceFormatter(timestampFormatter: { _ in "t" }, pid: 1)
        XCTAssertEqual(formatter.line(for: .power(.hasPoweredOn), at: Date()), "timestamp=t event=power pid=1 power=has-powered-on")
        XCTAssertEqual(formatter.line(for: .stopping(reason: "signal"), at: Date()), "timestamp=t event=stopping pid=1 reason=signal")
    }
    func testSinkWritesOneCompleteUTF8LinePerEvent() {
        let writes = LockedDataWrites()
        let sink = StandardDaemonEvidenceSink(
            formatter: DaemonSpikeEvidenceFormatter(timestampFormatter: { _ in "t" }, pid: 1),
            now: { Date() },
            write: { writes.append($0) }
        )

        sink.emit(.power(.willSleep))
        sink.emit(.stopping(reason: "signal"))

        XCTAssertEqual(writes.strings, [
            "timestamp=t event=power pid=1 power=will-sleep\n",
            "timestamp=t event=stopping pid=1 reason=signal\n"
        ])
    }

}


private final class LockedDataWrites: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Data] = []
    func append(_ data: Data) { lock.lock(); storage.append(data); lock.unlock() }
    var strings: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage.compactMap { String(data: $0, encoding: .utf8) }
    }
}

private final class RecordingEvidenceSink: DaemonSpikeEvidenceSinking, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DaemonSpikeEvidenceEvent] = []
    func emit(_ event: DaemonSpikeEvidenceEvent) { lock.lock(); storage.append(event); lock.unlock() }
    var events: [DaemonSpikeEvidenceEvent] { lock.lock(); defer { lock.unlock() }; return storage }
}
