import Foundation

protocol LidAngleDecoding: Sendable {
    func decode(_ report: HIDReport) -> AngleDecodeResult
}

protocol ReportShapeDecoder: Sendable {
    func supports(_ report: HIDReport) -> Bool
    func decodeSupported(_ report: HIDReport) -> AngleDecodeResult
}

/// Exploratory decoder only. Hardware validation must confirm this payload shape.
struct UInt16TenthsDecoder: ReportShapeDecoder {
    func supports(_ report: HIDReport) -> Bool {
        report.bytes.count == 2
    }

    func decodeSupported(_ report: HIDReport) -> AngleDecodeResult {
        guard report.bytes.count == 2 else {
            return .malformed("expected exactly 2 bytes")
        }

        let rawValue = UInt16(report.bytes[0]) | (UInt16(report.bytes[1]) << 8)
        let angle = Double(rawValue) / 10.0

        guard (0...180).contains(angle) else {
            return .outOfRange(angle)
        }

        return .decoded(angle)
    }
}

struct CompositeLidAngleDecoder: LidAngleDecoding {
    let decoders: [any ReportShapeDecoder]

    func decode(_ report: HIDReport) -> AngleDecodeResult {
        guard let decoder = decoders.first(where: { $0.supports(report) }) else {
            return .unsupported(reportLength: report.bytes.count)
        }
        return decoder.decodeSupported(report)
    }
}
