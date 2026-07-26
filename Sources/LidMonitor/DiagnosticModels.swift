import Foundation

enum DiagnosticMode: Equatable, Sendable {
    case list
    case watch
    case autoSleep(AutoSleepExecutionMode, LidSleepPolicy)
}

enum AutoSleepExecutionMode: Equatable, Sendable {
    case dryRun
    case executeSleep
}

struct LidSleepPolicy: Equatable, Sendable {
    let sleepThreshold: Int
    let reopenThreshold: Int
    let debounce: TimeInterval
    let wakeCooldown: TimeInterval

    static let calibratedDefault = try! LidSleepPolicy(
        sleepThreshold: 68,
        reopenThreshold: 75,
        debounce: 2.0,
        wakeCooldown: 5.0
    )

    init(
        sleepThreshold: Int,
        reopenThreshold: Int,
        debounce: TimeInterval,
        wakeCooldown: TimeInterval
    ) throws {
        guard (0...360).contains(sleepThreshold) else {
            throw LidSleepPolicyError.invalidSleepThreshold(sleepThreshold)
        }
        guard (0...360).contains(reopenThreshold) else {
            throw LidSleepPolicyError.invalidReopenThreshold(reopenThreshold)
        }
        guard reopenThreshold > sleepThreshold else {
            throw LidSleepPolicyError.invalidThresholdRelationship
        }
        guard debounce.isFinite, debounce > 0 else {
            throw LidSleepPolicyError.invalidDebounce(debounce)
        }
        guard wakeCooldown.isFinite, wakeCooldown >= 0 else {
            throw LidSleepPolicyError.invalidWakeCooldown(wakeCooldown)
        }

        self.sleepThreshold = sleepThreshold
        self.reopenThreshold = reopenThreshold
        self.debounce = debounce
        self.wakeCooldown = wakeCooldown
    }
}

enum LidSleepPolicyError: Error, Equatable, Sendable {
    case invalidSleepThreshold(Int)
    case invalidReopenThreshold(Int)
    case invalidThresholdRelationship
    case invalidDebounce(TimeInterval)
    case invalidWakeCooldown(TimeInterval)
}

struct CLIOptions: Equatable, Sendable {
    let mode: DiagnosticMode
    let includeRaw: Bool
    let duration: TimeInterval?
}

enum CLIParseError: Error, Equatable, Sendable {
    case conflictingModes
    case autoSleepRequiresExecutionMode
    case executionModeRequiresAutoSleep
    case conflictingExecutionModes
    case autoSleepRejectsDiagnosticOption(String)
    case policyOptionRequiresAutoSleep(String)
    case missingOptionValue(String)
    case invalidIntegerOption(String, String)
    case invalidNumberOption(String, String)
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

enum ClamshellState: Equatable, Sendable {
    case open
    case closed
    case unavailable
}
