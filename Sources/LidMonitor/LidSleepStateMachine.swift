import Foundation

enum LidSleepState: Equatable, Sendable {
    case cooldown
    case disarmed
    case open
    case closingCandidate(deadline: Date)
    case triggered
}

enum LidSleepEvent: Equatable, Sendable {
    case angleChanged(Int, at: Date)
    case debounceElapsed(at: Date)
    case cooldownElapsed(at: Date)
    case systemDidWake(at: Date)
    case dataInvalid(at: Date)
}

enum LidSleepEffect: Equatable, Sendable {
    case scheduleDebounce(deadline: Date)
    case cancelDebounce
    case requestSleep
    case stateChanged(LidSleepState)
}

struct LidSleepStateMachine: Sendable {
    private let policy: LidSleepPolicy
    private(set) var state: LidSleepState = .cooldown
    private var latestAngle: Int?

    init(policy: LidSleepPolicy) {
        self.policy = policy
    }

    mutating func handle(_ event: LidSleepEvent) -> [LidSleepEffect] {
        switch event {
        case let .angleChanged(angle, at: timestamp):
            guard (0...360).contains(angle) else {
                return handleInvalidData()
            }
            latestAngle = angle
            return handleAngle(angle, at: timestamp)

        case let .debounceElapsed(at: timestamp):
            return handleDebounceElapsed(at: timestamp)

        case .cooldownElapsed:
            if let latestAngle, latestAngle >= policy.reopenThreshold {
                return transition(to: .open)
            }
            return transition(to: .disarmed)

        case .systemDidWake:
            latestAngle = nil
            var effects: [LidSleepEffect] = []
            if case .closingCandidate = state {
                effects.append(.cancelDebounce)
            }
            state = .cooldown
            effects.append(.stateChanged(.cooldown))
            return effects

        case .dataInvalid:
            return handleInvalidData()
        }
    }

    private mutating func handleAngle(
        _ angle: Int,
        at timestamp: Date
    ) -> [LidSleepEffect] {
        switch state {
        case .cooldown:
            return []

        case .disarmed:
            guard angle >= policy.reopenThreshold else { return [] }
            return transition(to: .open)

        case .open:
            guard angle <= policy.sleepThreshold else { return [] }
            let deadline = timestamp.addingTimeInterval(policy.debounce)
            state = .closingCandidate(deadline: deadline)
            return [
                .stateChanged(.closingCandidate(deadline: deadline)),
                .scheduleDebounce(deadline: deadline)
            ]

        case .closingCandidate:
            guard angle > policy.sleepThreshold else { return [] }
            state = .open
            return [.cancelDebounce, .stateChanged(.open)]

        case .triggered:
            guard angle >= policy.reopenThreshold else { return [] }
            return transition(to: .open)
        }
    }

    private mutating func handleDebounceElapsed(
        at timestamp: Date
    ) -> [LidSleepEffect] {
        guard case let .closingCandidate(deadline) = state,
              timestamp >= deadline,
              let latestAngle,
              latestAngle <= policy.sleepThreshold else {
            return []
        }

        state = .triggered
        return [.stateChanged(.triggered), .requestSleep]
    }

    private mutating func handleInvalidData() -> [LidSleepEffect] {
        latestAngle = nil
        guard case .closingCandidate = state else { return [] }
        state = .open
        return [.cancelDebounce, .stateChanged(.open)]
    }

    private mutating func transition(
        to newState: LidSleepState
    ) -> [LidSleepEffect] {
        guard state != newState else { return [] }
        state = newState
        return [.stateChanged(newState)]
    }
}
