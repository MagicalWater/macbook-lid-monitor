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
