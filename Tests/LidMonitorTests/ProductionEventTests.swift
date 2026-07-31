import Foundation
import XCTest
@testable import LidMonitorCore

final class ProductionEventTests: XCTestCase {
    func testStableLifecycleAndErrorFormattingRedactsRawReports() {
        let formatter = ProductionEventFormatter(
            timestamp: { _ in "2026-07-27T00:00:00Z" },
            pid: 42
        )
        XCTAssertEqual(
            formatter.line(for: .started(mode: .dryRun, profileID: "profile"), at: Date()),
            "timestamp=2026-07-27T00:00:00Z event=started pid=42 mode=dry-run profile=profile"
        )
        XCTAssertEqual(
            formatter.line(for: .degraded(code: "unsupported-report"), at: Date()),
            "timestamp=2026-07-27T00:00:00Z event=degraded pid=42 code=unsupported-report"
        )
        XCTAssertFalse(formatter.line(for: .degraded(code: "unsupported-report"), at: Date()).contains("raw="))
        XCTAssertEqual(
            formatter.line(for: .sleepRequested, at: Date()),
            "timestamp=2026-07-27T00:00:00Z event=sleep-requested pid=42"
        )
        XCTAssertEqual(
            formatter.line(for: .transition(name: "candidate-started"), at: Date()),
            "timestamp=2026-07-27T00:00:00Z event=transition pid=42 name=candidate-started"
        )
        for name in [
            "startup-closed-candidate",
            "startup-closed-cancelled",
            "startup-closed-debounce-elapsed",
        ] {
            let line = formatter.line(for: .transition(name: name), at: Date())
            XCTAssertEqual(
                line,
                "timestamp=2026-07-27T00:00:00Z event=transition pid=42 name=\(name)"
            )
            XCTAssertFalse(line.contains("sensor="))
            XCTAssertFalse(line.contains("raw="))
        }
    }

    func testSensorValueAppearsOnlyOnAllowedTransitionEvent() {
        let formatter = ProductionEventFormatter(timestamp: { _ in "t" }, pid: 1)
        XCTAssertTrue(formatter.line(for: .stateChanged(.monitoringArmed, sensorValue: 80), at: Date()).contains("sensor=80"))
        XCTAssertFalse(formatter.line(for: .healthChanged(.degradedFailOpen), at: Date()).contains("sensor="))
    }

    func testSinkWritesAtomicLines() {
        let recorder = DataRecorder()
        let sink = ProductionEventSink(
            formatter: ProductionEventFormatter(timestamp: { _ in "t" }, pid: 1),
            now: Date.init,
            write: recorder.write
        )
        sink.emit(.stopping(reason: "signal"))
        XCTAssertEqual(String(decoding: recorder.values[0], as: UTF8.self), "timestamp=t event=stopping pid=1 reason=signal\n")
    }
}

private final class DataRecorder: @unchecked Sendable {
    private(set) var values: [Data] = []
    func write(_ data: Data) { values.append(data) }
}
