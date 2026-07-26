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
    let closeDebounce: TimeInterval
    let startupCooldown: TimeInterval
    let wakeRecovery: TimeInterval

    static let calibratedDefault = try! LidSleepPolicy(
        sleepThreshold: 68,
        reopenThreshold: 75,
        closeDebounce: 2.0,
        startupCooldown: 5.0,
        wakeRecovery: 15.0
    )

    init(
        sleepThreshold: Int,
        reopenThreshold: Int,
        closeDebounce: TimeInterval,
        startupCooldown: TimeInterval,
        wakeRecovery: TimeInterval
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
        guard closeDebounce.isFinite, closeDebounce > 0 else {
            throw LidSleepPolicyError.invalidCloseDebounce(closeDebounce)
        }
        guard startupCooldown.isFinite, startupCooldown >= 0 else {
            throw LidSleepPolicyError.invalidStartupCooldown(startupCooldown)
        }
        guard wakeRecovery.isFinite, wakeRecovery > 0 else {
            throw LidSleepPolicyError.invalidWakeRecovery(wakeRecovery)
        }

        self.sleepThreshold = sleepThreshold
        self.reopenThreshold = reopenThreshold
        self.closeDebounce = closeDebounce
        self.startupCooldown = startupCooldown
        self.wakeRecovery = wakeRecovery
    }
}

enum LidSleepPolicyError: Error, Equatable, Sendable {
    case invalidSleepThreshold(Int)
    case invalidReopenThreshold(Int)
    case invalidThresholdRelationship
    case invalidCloseDebounce(TimeInterval)
    case invalidStartupCooldown(TimeInterval)
    case invalidWakeRecovery(TimeInterval)
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
    case obsoleteWakeCooldownOption
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
