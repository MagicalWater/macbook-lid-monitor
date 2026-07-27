import Foundation
import IOKit
import IOKit.pwr_mgt

protocol SleepRequesting: AnyObject, Sendable {
    func requestSleep() throws
}

protocol SystemSleepOperating: Sendable {
    func requestSleep() throws
}

enum AutoSleepOperationalEvent: Equatable, Sendable {
    case sleepRequestAttempted
    case wouldSleep
    case sleepRequested
    case sleepRequestFailed(String)
}

enum AutoSleepTransitionEvent: Equatable, Sendable {
    case rearmed
    case candidateStarted
    case candidateCancelled
    case triggered
    case disarmed
    case startupCooldown
    case wakeRecovery
    case recoveryResleep
    case recoverySensorUnavailable
}

final class DryRunSleepRequester: SleepRequesting, @unchecked Sendable {
    private let onEvent: @Sendable (AutoSleepOperationalEvent) -> Void

    init(
        onEvent: @escaping @Sendable (AutoSleepOperationalEvent) -> Void
    ) {
        self.onEvent = onEvent
    }

    func requestSleep() throws {
        onEvent(.wouldSleep)
    }
}

final class MacOSSleepRequester: SleepRequesting, @unchecked Sendable {
    private let operation: SystemSleepOperating
    private let onEvent: @Sendable (AutoSleepOperationalEvent) -> Void

    init(
        operation: SystemSleepOperating,
        onEvent: @escaping @Sendable (AutoSleepOperationalEvent) -> Void = { _ in }
    ) {
        self.operation = operation
        self.onEvent = onEvent
    }

    func requestSleep() throws {
        try operation.requestSleep()
        onEvent(.sleepRequested)
    }
}

enum IOKitSystemSleepError: Error, Equatable, Sendable, CustomStringConvertible {
    case powerManagementUnavailable
    case requestFailed(IOReturn)

    var description: String {
        switch self {
        case .powerManagementUnavailable:
            return "power-management-unavailable"
        case let .requestFailed(code):
            return "iokit-request-failed(\(code))"
        }
    }
}

func stableSleepErrorDescription(_ error: Error) -> String {
    return String(describing: error)
}

struct IOKitSystemSleepOperation: SystemSleepOperating {
    func requestSleep() throws {
        let connection = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
        guard connection != 0 else {
            throw IOKitSystemSleepError.powerManagementUnavailable
        }
        defer { IOServiceClose(connection) }

        let result = IOPMSleepSystem(connection)
        guard result == kIOReturnSuccess else {
            throw IOKitSystemSleepError.requestFailed(result)
        }
    }
}
