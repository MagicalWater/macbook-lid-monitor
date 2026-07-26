import Foundation
import XCTest
@testable import LidMonitor

final class OutputFormatterTests: XCTestCase {
    func testAutoSleepOperationalEventsUseTransitionOnlyMessages() {
        let formatter = OutputFormatter()

        XCTAssertEqual(
            formatter.autoSleepLine(.wouldSleep),
            "auto-sleep: would-sleep"
        )
        XCTAssertEqual(
            formatter.autoSleepLine(.sleepRequested),
            "auto-sleep: sleep-requested"
        )
    }

    func testAutoSleepStateTransitionsUseCompactMessages() {
        let formatter = OutputFormatter(timeZone: TimeZone(secondsFromGMT: 0)!)

        XCTAssertEqual(formatter.autoSleepTransitionLine(.disarmed), "auto-sleep: disarmed")
        XCTAssertEqual(formatter.autoSleepTransitionLine(.rearmed), "auto-sleep: rearmed")
        XCTAssertEqual(
            formatter.autoSleepTransitionLine(.candidateStarted),
            "auto-sleep: candidate-started"
        )
        XCTAssertEqual(formatter.autoSleepTransitionLine(.triggered), "auto-sleep: triggered")
    }

    func testDecodedWatchLine() {
        let formatter = OutputFormatter(
            timeZone: TimeZone(secondsFromGMT: 8 * 3600)!
        )
        let date = Date(timeIntervalSince1970: 1_721_990_201)

        XCTAssertEqual(
            formatter.watchLine(
                timestamp: date,
                result: .decoded(103.4),
                rawBytes: nil,
                clamshell: .open
            ),
            "2024-07-26T18:36:41+08:00 angle=103.4 clamshell=open"
        )
    }

    func testUnsupportedLineIncludesLength() {
        let formatter = OutputFormatter(
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let line = formatter.watchLine(
            timestamp: .distantPast,
            result: .unsupported(reportLength: 8),
            rawBytes: nil,
            clamshell: .unavailable
        )

        XCTAssertTrue(line.contains("angle=unsupported"))
        XCTAssertTrue(line.contains("reportLength=8"))
        XCTAssertTrue(line.contains("clamshell=unavailable"))
    }

    func testRawBytesUseUppercaseHex() {
        let formatter = OutputFormatter(
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        let line = formatter.watchLine(
            timestamp: Date(timeIntervalSince1970: 0),
            result: .decoded(1.0),
            rawBytes: [0x00, 0xAF, 0x10],
            clamshell: .closed
        )

        XCTAssertTrue(line.contains("raw=00 AF 10"))
        XCTAssertTrue(line.contains("clamshell=closed"))
    }

    func testCandidateLineIncludesScoreReasonsAndMetadata() {
        let descriptor = HIDDeviceDescriptor(
            registryEntryID: 42,
            name: "Apple Lid Sensor",
            vendorID: 0x05AC,
            productID: 0x1234,
            usagePage: 0xFF00,
            usage: 1,
            transport: "SPI",
            inputClass: .other
        )
        let candidate = CandidateScore(
            descriptor: descriptor,
            score: 55,
            reasons: ["name:lid=+30", "name:sensor=+10"]
        )

        let line = OutputFormatter().candidateLine(candidate, selectable: true)

        XCTAssertTrue(line.contains("score=55"))
        XCTAssertTrue(line.contains("registryID=42"))
        XCTAssertTrue(line.contains("vendorID=0x05AC"))
        XCTAssertTrue(line.contains("selectable=yes"))
    }
}
