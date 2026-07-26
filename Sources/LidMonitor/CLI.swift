import Foundation

enum CLIParser {
    static func parse(_ arguments: [String]) throws -> CLIOptions {
        var diagnosticMode: DiagnosticMode = .watch
        var explicitDiagnosticMode: DiagnosticMode?
        var includeRaw = false
        var duration: TimeInterval?

        var autoSleepRequested = false
        var executionMode: AutoSleepExecutionMode?
        var sleepThreshold = LidSleepPolicy.calibratedDefault.sleepThreshold
        var reopenThreshold = LidSleepPolicy.calibratedDefault.reopenThreshold
        var closeDebounce = LidSleepPolicy.calibratedDefault.closeDebounce
        var startupCooldown = LidSleepPolicy.calibratedDefault.startupCooldown
        var wakeRecovery = LidSleepPolicy.calibratedDefault.wakeRecovery
        var policyOptions: Set<String> = []

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--list":
                try setDiagnosticMode(.list, current: &explicitDiagnosticMode)
                diagnosticMode = .list
            case "--watch":
                try setDiagnosticMode(.watch, current: &explicitDiagnosticMode)
                diagnosticMode = .watch
            case "--auto-sleep":
                guard explicitDiagnosticMode == nil else {
                    throw CLIParseError.conflictingModes
                }
                autoSleepRequested = true
            case "--dry-run":
                try setExecutionMode(.dryRun, current: &executionMode)
            case "--execute-sleep":
                try setExecutionMode(.executeSleep, current: &executionMode)
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
            case "--sleep-threshold":
                sleepThreshold = try parseIntegerOption(
                    argument,
                    arguments: arguments,
                    index: &index
                )
                policyOptions.insert(argument)
            case "--reopen-threshold":
                reopenThreshold = try parseIntegerOption(
                    argument,
                    arguments: arguments,
                    index: &index
                )
                policyOptions.insert(argument)
            case "--debounce":
                closeDebounce = try parseNumberOption(
                    argument,
                    arguments: arguments,
                    index: &index
                )
                policyOptions.insert(argument)
            case "--startup-cooldown":
                startupCooldown = try parseNumberOption(
                    argument,
                    arguments: arguments,
                    index: &index
                )
                policyOptions.insert(argument)
            case "--wake-recovery":
                wakeRecovery = try parseNumberOption(
                    argument,
                    arguments: arguments,
                    index: &index
                )
                policyOptions.insert(argument)
            case "--wake-cooldown":
                throw CLIParseError.obsoleteWakeCooldownOption
            default:
                throw CLIParseError.unknownOption(argument)
            }

            index += 1
        }

        if !autoSleepRequested {
            if executionMode != nil {
                throw CLIParseError.executionModeRequiresAutoSleep
            }
            if let option = policyOptions.sorted().first {
                throw CLIParseError.policyOptionRequiresAutoSleep(option)
            }
            if diagnosticMode == .list && includeRaw {
                throw CLIParseError.rawRequiresWatch
            }
            if diagnosticMode == .list && duration != nil {
                throw CLIParseError.durationRequiresWatch
            }

            return CLIOptions(
                mode: diagnosticMode,
                includeRaw: includeRaw,
                duration: duration
            )
        }

        guard explicitDiagnosticMode == nil else {
            throw CLIParseError.conflictingModes
        }
        guard let executionMode else {
            throw CLIParseError.autoSleepRequiresExecutionMode
        }
        if includeRaw {
            throw CLIParseError.autoSleepRejectsDiagnosticOption("--raw")
        }
        if duration != nil {
            throw CLIParseError.autoSleepRejectsDiagnosticOption("--duration")
        }

        let policy = try LidSleepPolicy(
            sleepThreshold: sleepThreshold,
            reopenThreshold: reopenThreshold,
            closeDebounce: closeDebounce,
            startupCooldown: startupCooldown,
            wakeRecovery: wakeRecovery
        )

        return CLIOptions(
            mode: .autoSleep(executionMode, policy),
            includeRaw: false,
            duration: nil
        )
    }

    private static func setDiagnosticMode(
        _ requested: DiagnosticMode,
        current: inout DiagnosticMode?
    ) throws {
        if let current, current != requested {
            throw CLIParseError.conflictingModes
        }
        current = requested
    }

    private static func setExecutionMode(
        _ requested: AutoSleepExecutionMode,
        current: inout AutoSleepExecutionMode?
    ) throws {
        if let current, current != requested {
            throw CLIParseError.conflictingExecutionModes
        }
        current = requested
    }

    private static func nextValue(
        for option: String,
        arguments: [String],
        index: inout Int
    ) throws -> String {
        index += 1
        guard index < arguments.count else {
            throw CLIParseError.missingOptionValue(option)
        }
        return arguments[index]
    }

    private static func parseIntegerOption(
        _ option: String,
        arguments: [String],
        index: inout Int
    ) throws -> Int {
        let rawValue = try nextValue(
            for: option,
            arguments: arguments,
            index: &index
        )
        guard let parsed = Int(rawValue) else {
            throw CLIParseError.invalidIntegerOption(option, rawValue)
        }
        return parsed
    }

    private static func parseNumberOption(
        _ option: String,
        arguments: [String],
        index: inout Int
    ) throws -> TimeInterval {
        let rawValue = try nextValue(
            for: option,
            arguments: arguments,
            index: &index
        )
        guard let parsed = TimeInterval(rawValue) else {
            throw CLIParseError.invalidNumberOption(option, rawValue)
        }
        return parsed
    }
}
