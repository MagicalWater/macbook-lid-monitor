import XCTest
@testable import LidMonitor

final class CandidateRankingTests: XCTestCase {
    func testKeyboardIsExcludedEvenWhenNameContainsSensor() {
        let keyboard = HIDDeviceDescriptor.fixture(
            name: "Apple Sensor Keyboard",
            vendorID: 0x05AC,
            productID: 1,
            usagePage: 0x01,
            usage: 0x06,
            inputClass: .keyboard
        )

        XCTAssertTrue(CandidateRanker.rank([keyboard]).isEmpty)
    }

    func testLidAngleIdentityRanksAboveGenericAppleDevice() {
        let lid = HIDDeviceDescriptor.fixture(
            registryEntryID: 2,
            name: "Apple Lid Angle Sensor",
            vendorID: 0x05AC,
            productID: 2,
            usagePage: 0xFF00,
            usage: 1,
            inputClass: .other
        )
        let generic = HIDDeviceDescriptor.fixture(
            registryEntryID: 3,
            name: "Apple Internal Device",
            vendorID: 0x05AC,
            productID: 3,
            usagePage: 0xFF00,
            usage: 2,
            inputClass: .other
        )

        let ranked = CandidateRanker.rank([generic, lid])

        XCTAssertEqual(ranked.first?.descriptor.name, "Apple Lid Angle Sensor")
        XCTAssertGreaterThanOrEqual(
            ranked.first?.score ?? 0,
            CandidateRanker.minimumSelectableScore
        )
    }

    func testAppleVendorAloneDoesNotMeetThreshold() {
        let generic = HIDDeviceDescriptor.fixture(
            name: "Apple Internal Device",
            vendorID: 0x05AC,
            productID: 3,
            usagePage: 0xFF00,
            usage: 2,
            inputClass: .other
        )
        let ranked = CandidateRanker.rank([generic])

        XCTAssertLessThan(
            ranked.first?.score ?? 0,
            CandidateRanker.minimumSelectableScore
        )
    }

    func testReasonsExplainEveryAwardedScoreComponent() throws {
        let lid = HIDDeviceDescriptor.fixture(
            name: "Apple Hinge Sensor",
            vendorID: 0x05AC,
            productID: 4,
            usagePage: 0xFF00,
            usage: 1,
            inputClass: .other
        )

        let candidate = try XCTUnwrap(CandidateRanker.rank([lid]).first)

        XCTAssertEqual(candidate.score, 55)
        XCTAssertEqual(candidate.reasons.count, 4)
    }

    func testEqualScoresSortByRegistryEntryID() {
        let later = HIDDeviceDescriptor.fixture(
            registryEntryID: 20,
            name: "Lid Sensor",
            vendorID: nil,
            productID: nil,
            usagePage: nil,
            usage: nil,
            inputClass: .other
        )
        let earlier = HIDDeviceDescriptor.fixture(
            registryEntryID: 10,
            name: "Lid Sensor",
            vendorID: nil,
            productID: nil,
            usagePage: nil,
            usage: nil,
            inputClass: .other
        )

        XCTAssertEqual(
            CandidateRanker.rank([later, earlier]).map(\.descriptor.registryEntryID),
            [10, 20]
        )
    }
}

private extension HIDDeviceDescriptor {
    static func fixture(
        registryEntryID: UInt64 = 1,
        name: String,
        vendorID: Int?,
        productID: Int?,
        usagePage: Int?,
        usage: Int?,
        transport: String? = nil,
        inputClass: HIDInputClass
    ) -> HIDDeviceDescriptor {
        HIDDeviceDescriptor(
            registryEntryID: registryEntryID,
            name: name,
            vendorID: vendorID,
            productID: productID,
            usagePage: usagePage,
            usage: usage,
            transport: transport,
            inputClass: inputClass
        )
    }
}
