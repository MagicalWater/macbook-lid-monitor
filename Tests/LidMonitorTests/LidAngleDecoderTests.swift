import Foundation
import XCTest
@testable import LidMonitor

final class LidAngleDecoderTests: XCTestCase {
    private let decoder = CompositeLidAngleDecoder(decoders: [UInt16TenthsDecoder()])

    func testTwoByteLittleEndianTenthsDecode() {
        let report = HIDReport(reportID: 0, bytes: [0x10, 0x04], timestamp: .distantPast)
        XCTAssertEqual(decoder.decode(report), .decoded(104.0))
    }

    func testUnsupportedLengthIsExplicit() {
        let report = HIDReport(reportID: 0, bytes: [0x01, 0x02, 0x03], timestamp: .distantPast)
        XCTAssertEqual(decoder.decode(report), .unsupported(reportLength: 3))
    }

    func testAngleAbovePhysicalLimitIsRejected() {
        let report = HIDReport(reportID: 0, bytes: [0xD0, 0x07], timestamp: .distantPast)
        XCTAssertEqual(decoder.decode(report), .outOfRange(200.0))
    }

    func testEmptyReportIsUnsupportedWithoutIndexing() {
        let report = HIDReport(reportID: 0, bytes: [], timestamp: .distantPast)
        XCTAssertEqual(decoder.decode(report), .unsupported(reportLength: 0))
    }
}
