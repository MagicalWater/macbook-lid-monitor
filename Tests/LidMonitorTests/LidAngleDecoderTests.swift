import Foundation
import XCTest
@testable import LidMonitorCore

final class LidAngleDecoderTests: XCTestCase {
    private let decoder = CompositeLidAngleDecoder(
        decoders: [ReportID1DegreesDecoder(), UInt16TenthsDecoder()]
    )

    func testObservedThreeByteReportDecodesIntegerDegrees() {
        let report = HIDReport(
            reportID: 1,
            bytes: [0x01, 0xAC, 0x00],
            timestamp: .distantPast
        )

        XCTAssertEqual(decoder.decode(report), .decoded(172.0))
    }

    func testThreeByteDecoderRejectsWrongEmbeddedReportID() {
        let report = HIDReport(
            reportID: 2,
            bytes: [0x02, 0xAC, 0x00],
            timestamp: .distantPast
        )

        XCTAssertEqual(decoder.decode(report), .unsupported(reportLength: 3))
    }

    func testTwoByteLittleEndianTenthsDecode() {
        let report = HIDReport(reportID: 0, bytes: [0x10, 0x04], timestamp: .distantPast)
        XCTAssertEqual(decoder.decode(report), .decoded(104.0))
    }

    func testUnsupportedLengthIsExplicit() {
        let report = HIDReport(reportID: 0, bytes: [0x01, 0x02, 0x03], timestamp: .distantPast)
        XCTAssertEqual(decoder.decode(report), .unsupported(reportLength: 3))
    }

    func testObservedAngleAbove180RemainsValid() {
        let report = HIDReport(reportID: 1, bytes: [0x01, 0xB9, 0x00], timestamp: .distantPast)
        XCTAssertEqual(decoder.decode(report), .decoded(185.0))
    }

    func testAngleAboveSensorRangeIsRejected() {
        let report = HIDReport(reportID: 0, bytes: [0x1A, 0x0E], timestamp: .distantPast)
        XCTAssertEqual(decoder.decode(report), .outOfRange(361.0))
    }

    func testEmptyReportIsUnsupportedWithoutIndexing() {
        let report = HIDReport(reportID: 0, bytes: [], timestamp: .distantPast)
        XCTAssertEqual(decoder.decode(report), .unsupported(reportLength: 0))
    }
}
