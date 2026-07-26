import Foundation

enum CLIParser {
    static func parse(_ arguments: [String]) throws -> CLIOptions {
        var mode: DiagnosticMode = .watch
        var explicitMode: DiagnosticMode?
        var includeRaw = false
        var duration: TimeInterval?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--list":
                try setMode(.list, current: &explicitMode)
                mode = .list
            case "--watch":
                try setMode(.watch, current: &explicitMode)
                mode = .watch
            case "--raw":
                includeRaw = true
            case "--duration":
                index += 1
                guard index < arguments.count else {
                    throw CLIParseError.missingDurationValue
                }

                let rawValue = arguments[index]
                guard let parsed = TimeInterval(rawValue), parsed.isFinite, parsed > 0 else {
                    throw CLIParseError.invalidDuration(rawValue)
                }
                duration = parsed
            default:
                throw CLIParseError.unknownOption(argument)
            }

            index += 1
        }

        if mode == .list && includeRaw {
            throw CLIParseError.rawRequiresWatch
        }

        if mode == .list && duration != nil {
            throw CLIParseError.durationRequiresWatch
        }

        return CLIOptions(mode: mode, includeRaw: includeRaw, duration: duration)
    }

    private static func setMode(
        _ requested: DiagnosticMode,
        current: inout DiagnosticMode?
    ) throws {
        if let current, current != requested {
            throw CLIParseError.conflictingModes
        }
        current = requested
    }
}
