import Foundation

protocol LidAngleDecoding: Sendable {
    func decode(_ report: HIDReport) -> AngleDecodeResult
}

protocol ReportShapeDecoder: Sendable {
    func supports(_ report: HIDReport) -> Bool
    func decodeSupported(_ report: HIDReport) -> AngleDecodeResult
}

/// Verified on the user's M1 Pro: [report ID 1, low byte, high byte].
struct ReportID1DegreesDecoder: ReportShapeDecoder {
    func supports(_ report: HIDReport) -> Bool {
        report.reportID == 1 && report.bytes.count == 3 && report.bytes[0] == 1
    }

    func decodeSupported(_ report: HIDReport) -> AngleDecodeResult {
        guard report.bytes.count == 3, report.bytes[0] == 1 else {
            return .malformed("expected report ID 1 with exactly 3 bytes")
        }

        let rawValue = UInt16(report.bytes[1]) | (UInt16(report.bytes[2]) << 8)
        let angle = Double(rawValue)

        guard (0...360).contains(angle) else {
            return .outOfRange(angle)
        }

        return .decoded(angle)
    }
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

        guard (0...360).contains(angle) else {
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
