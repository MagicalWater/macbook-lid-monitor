import Foundation

enum DiagnosticMode: Equatable, Sendable {
    case list
    case watch
}

struct CLIOptions: Equatable, Sendable {
    let mode: DiagnosticMode
    let includeRaw: Bool
    let duration: TimeInterval?
}

enum CLIParseError: Error, Equatable, Sendable {
    case conflictingModes
    case rawRequiresWatch
    case durationRequiresWatch
    case missingDurationValue
    case invalidDuration(String)
    case unknownOption(String)
}

enum ExitCode: Int32 {
    case success = 0
    case usage = 64
    case unavailable = 69
    case internalError = 70
    case ioFailure = 74
}

enum AppVersion {
    static let current = "0.1.0"
}

struct HIDReport: Equatable, Sendable {
    let reportID: UInt32
    let bytes: [UInt8]
    let timestamp: Date
}

enum AngleDecodeResult: Equatable, Sendable {
    case decoded(Double)
    case unsupported(reportLength: Int)
    case malformed(String)
    case outOfRange(Double)
}
