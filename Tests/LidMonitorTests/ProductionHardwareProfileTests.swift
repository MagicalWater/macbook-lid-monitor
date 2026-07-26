import Foundation
import XCTest
@testable import LidMonitorCore

final class ProductionHardwareProfileTests: XCTestCase {
    func testExactM1ProProfileResolvesWithBoundDecoder() throws {
        let descriptor = makeDescriptor()
        let resolution = try LidHardwareProfileRegistry.production.resolve(
            profileID: "m1-pro-0x8104-report-id-1-v1",
            descriptors: [descriptor]
        )

        XCTAssertEqual(resolution.profile.id, "m1-pro-0x8104-report-id-1-v1")
        XCTAssertEqual(resolution.descriptor, descriptor)
        XCTAssertEqual(
            resolution.decoder.decode(
                HIDReport(reportID: 1, bytes: [1, 68, 0], timestamp: Date())
            ),
            .decoded(68)
        )
    }

    func testTransportMismatchAndUnknownProfileFailOpen() {
        XCTAssertThrowsError(
            try LidHardwareProfileRegistry.production.resolve(
                profileID: "m1-pro-0x8104-report-id-1-v1",
                descriptors: [makeDescriptor(transport: "USB")]
            )
        ) { error in
            XCTAssertEqual(error as? LidHardwareProfileError, .noExactDeviceMatch)
        }

        XCTAssertThrowsError(
            try LidHardwareProfileRegistry.production.resolve(
                profileID: "unknown",
                descriptors: [makeDescriptor()]
            )
        ) { error in
            XCTAssertEqual(error as? LidHardwareProfileError, .unknownProfile("unknown"))
        }
    }

    func testDuplicateExactDevicesFailOpen() {
        XCTAssertThrowsError(
            try LidHardwareProfileRegistry.production.resolve(
                profileID: "m1-pro-0x8104-report-id-1-v1",
                descriptors: [makeDescriptor(registryID: 1), makeDescriptor(registryID: 2)]
            )
        ) { error in
            XCTAssertEqual(error as? LidHardwareProfileError, .ambiguousExactDeviceMatch(2))
        }
    }

    func testDiagnosticRankingCannotAuthorizeGenericAppleDevice() {
        let generic = makeDescriptor(productID: 0x9999)
        XCTAssertFalse(CandidateRanker.rank([generic]).isEmpty)
        XCTAssertThrowsError(
            try LidHardwareProfileRegistry.production.resolve(
                profileID: "m1-pro-0x8104-report-id-1-v1",
                descriptors: [generic]
            )
        ) { error in
            XCTAssertEqual(error as? LidHardwareProfileError, .noExactDeviceMatch)
        }
    }

    func testProfileDecoderRejectsUnknownReportShape() throws {
        let resolution = try LidHardwareProfileRegistry.production.resolve(
            profileID: "m1-pro-0x8104-report-id-1-v1",
            descriptors: [makeDescriptor()]
        )
        XCTAssertEqual(
            resolution.decoder.decode(
                HIDReport(reportID: 1, bytes: [1, 68], timestamp: Date())
            ),
            .unsupported(reportLength: 2)
        )
    }

    private func makeDescriptor(
        registryID: UInt64 = 1,
        productID: Int = 0x8104,
        transport: String = "SPU"
    ) -> HIDDeviceDescriptor {
        HIDDeviceDescriptor(
            registryEntryID: registryID,
            name: "Apple Hinge Orientation Sensor",
            vendorID: 0x05AC,
            productID: productID,
            usagePage: 0x0020,
            usage: 0x008A,
            transport: transport,
            inputClass: .other
        )
    }
}
