import Foundation

struct LidHardwareProfile: Equatable, Sendable {
    let id: String
    let vendorID: Int
    let productID: Int
    let usagePage: Int
    let usage: Int
    let transport: String
    let decoderKind: DecoderKind

    enum DecoderKind: Equatable, Sendable {
        case reportID1Degrees
    }

    func matches(_ descriptor: HIDDeviceDescriptor) -> Bool {
        descriptor.vendorID == vendorID
            && descriptor.productID == productID
            && descriptor.usagePage == usagePage
            && descriptor.usage == usage
            && descriptor.transport == transport
            && descriptor.inputClass == .other
    }

    func makeDecoder() -> any LidAngleDecoding {
        switch decoderKind {
        case .reportID1Degrees:
            return ProfileBoundLidAngleDecoder(decoder: ReportID1DegreesDecoder())
        }
    }
}

private struct ProfileBoundLidAngleDecoder: LidAngleDecoding {
    let decoder: any ReportShapeDecoder

    func decode(_ report: HIDReport) -> AngleDecodeResult {
        guard decoder.supports(report) else {
            return .unsupported(reportLength: report.bytes.count)
        }
        return decoder.decodeSupported(report)
    }
}

struct ResolvedLidHardwareProfile: Sendable {
    let profile: LidHardwareProfile
    let descriptor: HIDDeviceDescriptor
    let decoder: any LidAngleDecoding
}

enum LidHardwareProfileError: Error, Equatable, Sendable {
    case unknownProfile(String)
    case noExactDeviceMatch
    case ambiguousExactDeviceMatch(Int)
}
