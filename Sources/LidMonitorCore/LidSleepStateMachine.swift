import Foundation

enum LidSleepState: Equatable, Sendable {
    case startupCooldown
    case wakeRecovery(deadline: Date)
    case disarmed
    case open
    case closingCandidate(deadline: Date)
    case triggered
}

enum LidSleepEvent: Equatable, Sendable {
    case angleChanged(Int, at: Date)
    case closeDebounceElapsed(at: Date)
    case startupCooldownElapsed(at: Date)
    case wakeRecoveryElapsed(at: Date)
    case systemDidWake(at: Date)
    case sleepRequestFailed(at: Date)
    case dataInvalid(at: Date)
}

enum LidSleepEffect: Equatable, Sendable {
    case scheduleCloseDebounce(deadline: Date)
    case cancelCloseDebounce
    case scheduleWakeRecovery(deadline: Date)
    case cancelWakeRecovery
    case requestSleep
    case stateChanged(LidSleepState)
}

struct LidSleepStateMachine: Sendable {
    private let policy: LidSleepPolicy
    private let maximumSampleAge: TimeInterval
    private(set) var state: LidSleepState = .startupCooldown
    private var latestAngle: Int?
    private var latestSampleTimestamp: Date?
    private var latestWakeTimestamp: Date?

    init(policy: LidSleepPolicy, maximumSampleAge: TimeInterval = .infinity) {
        self.policy = policy
        self.maximumSampleAge = maximumSampleAge > 0 ? maximumSampleAge : 0
    }

    mutating func handle(_ event: LidSleepEvent) -> [LidSleepEffect] {
        switch event {
        case let .angleChanged(angle, at: timestamp):
            guard (0...360).contains(angle) else {
                return handleInvalidData()
            }
            latestAngle = angle
            latestSampleTimestamp = timestamp
            return handleAngle(angle, at: timestamp)

        case let .closeDebounceElapsed(at: timestamp):
            return handleCloseDebounceElapsed(at: timestamp)

        case .startupCooldownElapsed:
            if let latestAngle, latestAngle >= policy.reopenThreshold {
                return transition(to: .open)
            }
            return transition(to: .disarmed)

        case let .wakeRecoveryElapsed(at: timestamp):
            return handleWakeRecoveryElapsed(at: timestamp)

        case let .systemDidWake(at: timestamp):
            return handleSystemWake(at: timestamp)

        case .sleepRequestFailed:
            guard case .triggered = state else { return [] }
            return transition(to: .disarmed)

        case .dataInvalid:
            return handleInvalidData()
        }
    }

    private mutating func handleAngle(
        _ angle: Int,
        at timestamp: Date
    ) -> [LidSleepEffect] {
        switch state {
        case .startupCooldown:
            return []

        case .wakeRecovery:
            guard angle >= policy.reopenThreshold else { return [] }
            state = .open
            return [.cancelWakeRecovery, .stateChanged(.open)]

        case .disarmed:
            guard angle >= policy.reopenThreshold else { return [] }
            return transition(to: .open)

        case .open:
            guard angle <= policy.sleepThreshold else { return [] }
            let deadline = timestamp.addingTimeInterval(policy.closeDebounce)
            state = .closingCandidate(deadline: deadline)
            return [
                .stateChanged(.closingCandidate(deadline: deadline)),
                .scheduleCloseDebounce(deadline: deadline)
            ]

        case .closingCandidate:
            guard angle > policy.sleepThreshold else { return [] }
            state = .open
            return [.cancelCloseDebounce, .stateChanged(.open)]

        case .triggered:
            guard angle >= policy.reopenThreshold else { return [] }
            return transition(to: .open)
        }
    }

    private mutating func handleCloseDebounceElapsed(
        at timestamp: Date
    ) -> [LidSleepEffect] {
        guard case let .closingCandidate(deadline) = state,
              timestamp >= deadline,
              let latestAngle,
              isFresh(at: timestamp),
              latestAngle <= policy.sleepThreshold else {
            if case .closingCandidate = state, !isFresh(at: timestamp) {
                state = .open
                return [.cancelCloseDebounce, .stateChanged(.open)]
            }
            return []
        }

        state = .triggered
        return [.stateChanged(.triggered), .requestSleep]
    }

    private mutating func handleSystemWake(at timestamp: Date) -> [LidSleepEffect] {
        if let latestWakeTimestamp, timestamp <= latestWakeTimestamp {
            return []
        }
        latestWakeTimestamp = timestamp
        latestAngle = nil
        latestSampleTimestamp = nil
        var effects: [LidSleepEffect] = []
        if case .closingCandidate = state {
            effects.append(.cancelCloseDebounce)
        }
        if case .wakeRecovery = state {
            effects.append(.cancelWakeRecovery)
        }

        let deadline = timestamp.addingTimeInterval(policy.wakeRecovery)
        state = .wakeRecovery(deadline: deadline)
        effects.append(.stateChanged(.wakeRecovery(deadline: deadline)))
        effects.append(.scheduleWakeRecovery(deadline: deadline))
        return effects
    }

    private mutating func handleWakeRecoveryElapsed(
        at timestamp: Date
    ) -> [LidSleepEffect] {
        guard case let .wakeRecovery(deadline) = state,
              timestamp >= deadline else {
            return []
        }

        guard let latestAngle else {
            return transition(to: .disarmed)
        }
        guard isFresh(at: timestamp) else {
            return transition(to: .disarmed)
        }
        guard latestAngle < policy.reopenThreshold else {
            return transition(to: .open)
        }

        state = .triggered
        return [.stateChanged(.triggered), .requestSleep]
    }

    private mutating func handleInvalidData() -> [LidSleepEffect] {
        latestAngle = nil
        latestSampleTimestamp = nil
        guard case .closingCandidate = state else { return [] }
        state = .open
        return [.cancelCloseDebounce, .stateChanged(.open)]
    }

    private func isFresh(at timestamp: Date) -> Bool {
        guard let latestSampleTimestamp else { return false }
        return timestamp.timeIntervalSince(latestSampleTimestamp) <= maximumSampleAge
    }

    private mutating func transition(
        to newState: LidSleepState
    ) -> [LidSleepEffect] {
        guard state != newState else { return [] }
        state = newState
        return [.stateChanged(newState)]
    }
}
