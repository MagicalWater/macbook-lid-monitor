import Dispatch
import Foundation

final class LidSleepCoordinator: @unchecked Sendable {
    private let stream: HIDReportStreaming
    private let decoder: LidAngleDecoding
    private let scheduler: OneShotScheduling
    private let wakeObserver: SystemWakeObserving
    private let sleepRequester: SleepRequesting
    private let policy: LidSleepPolicy
    private let now: @Sendable () -> Date
    private let onOperationalEvent: @Sendable (AutoSleepOperationalEvent) -> Void
    private let onTransitionEvent: @Sendable (AutoSleepTransitionEvent) -> Void
    private let queue = DispatchQueue(label: "macbook-lid-monitor.coordinator")

    private var machine: LidSleepStateMachine
    private var closeDebounceTask: CancellableTask?
    private var startupCooldownTask: CancellableTask?
    private var wakeRecoveryTask: CancellableTask?
    private var lastReportedState: LidSleepState = .startupCooldown
    private var started = false

    init(
        stream: HIDReportStreaming,
        decoder: LidAngleDecoding,
        scheduler: OneShotScheduling,
        wakeObserver: SystemWakeObserving,
        sleepRequester: SleepRequesting,
        policy: LidSleepPolicy,
        maximumSampleAge: TimeInterval = .infinity,
        now: @escaping @Sendable () -> Date = Date.init,
        onOperationalEvent: @escaping @Sendable (AutoSleepOperationalEvent) -> Void = { _ in },
        onTransitionEvent: @escaping @Sendable (AutoSleepTransitionEvent) -> Void = { _ in }
    ) {
        self.stream = stream
        self.decoder = decoder
        self.scheduler = scheduler
        self.wakeObserver = wakeObserver
        self.sleepRequester = sleepRequester
        self.policy = policy
        self.now = now
        self.onOperationalEvent = onOperationalEvent
        self.onTransitionEvent = onTransitionEvent
        machine = LidSleepStateMachine(
            policy: policy,
            maximumSampleAge: maximumSampleAge > 0 ? maximumSampleAge : 0
        )
    }

    func start() throws {
        try queue.sync {
            guard !started else { return }
            started = true

            try wakeObserver.start { [weak self] date in
                self?.queue.sync {
                    self?.handleWake(at: date)
                }
            }

            onTransitionEvent(.startupCooldown)
            scheduleStartupCooldown(from: now())

            do {
                try stream.start { [weak self] report in
                    self?.queue.sync {
                        self?.handle(report)
                    }
                }
            } catch {
                started = false
                cancelAllTasks()
                wakeObserver.stop()
                throw error
            }
        }
    }

    func stop() {
        queue.sync {
            guard started else { return }
            started = false
            cancelAllTasks()
            wakeObserver.stop()
            stream.stop()
        }
    }

    private func handle(_ report: HIDReport) {
        guard started else { return }

        switch decoder.decode(report) {
        case let .decoded(value):
            guard value.isFinite,
                  value.rounded() == value,
                  let angle = Int(exactly: value) else {
                apply(machine.handle(.dataInvalid(at: report.timestamp)))
                return
            }
            apply(machine.handle(.angleChanged(angle, at: report.timestamp)))

        case .unsupported, .malformed, .outOfRange:
            apply(machine.handle(.dataInvalid(at: report.timestamp)))
        }
    }

    private func handleWake(at date: Date) {
        guard started else { return }
        startupCooldownTask?.cancel()
        startupCooldownTask = nil
        apply(machine.handle(.systemDidWake(at: date)))
    }

    private func scheduleStartupCooldown(from date: Date) {
        let deadline = date.addingTimeInterval(policy.startupCooldown)
        startupCooldownTask?.cancel()
        startupCooldownTask = scheduler.schedule(at: deadline) { [weak self] in
            self?.queue.sync {
                guard let self, self.started else { return }
                self.startupCooldownTask = nil
                self.apply(self.machine.handle(.startupCooldownElapsed(at: deadline)))
            }
        }
    }

    private func apply(_ effects: [LidSleepEffect]) {
        for effect in effects {
            switch effect {
            case let .scheduleCloseDebounce(deadline):
                closeDebounceTask?.cancel()
                closeDebounceTask = scheduler.schedule(at: deadline) { [weak self] in
                    self?.queue.sync {
                        guard let self, self.started else { return }
                        self.closeDebounceTask = nil
                        self.apply(self.machine.handle(.closeDebounceElapsed(at: deadline)))
                    }
                }

            case .cancelCloseDebounce:
                closeDebounceTask?.cancel()
                closeDebounceTask = nil

            case let .scheduleWakeRecovery(deadline):
                wakeRecoveryTask?.cancel()
                wakeRecoveryTask = scheduler.schedule(at: deadline) { [weak self] in
                    self?.queue.sync {
                        guard let self, self.started else { return }
                        self.wakeRecoveryTask = nil
                        self.apply(self.machine.handle(.wakeRecoveryElapsed(at: deadline)))
                    }
                }

            case .cancelWakeRecovery:
                wakeRecoveryTask?.cancel()
                wakeRecoveryTask = nil

            case .requestSleep:
                onOperationalEvent(.sleepRequestAttempted)
                do {
                    try sleepRequester.requestSleep()
                } catch {
                    onOperationalEvent(
                        .sleepRequestFailed(stableSleepErrorDescription(error))
                    )
                    apply(machine.handle(.sleepRequestFailed(at: now())))
                }

            case let .stateChanged(state):
                let previousState = lastReportedState
                lastReportedState = state

                switch state {
                case .open:
                    if case .closingCandidate = previousState {
                        onTransitionEvent(.candidateCancelled)
                    } else {
                        onTransitionEvent(.rearmed)
                    }
                case .closingCandidate: onTransitionEvent(.candidateStarted)
                case .triggered:
                    if case .wakeRecovery = previousState {
                        onTransitionEvent(.recoveryResleep)
                    } else {
                        onTransitionEvent(.triggered)
                    }
                case .disarmed:
                    if case .wakeRecovery = previousState {
                        onTransitionEvent(.recoverySensorUnavailable)
                    } else {
                        onTransitionEvent(.disarmed)
                    }
                case .startupCooldown:
                    onTransitionEvent(.startupCooldown)
                case .wakeRecovery:
                    onTransitionEvent(.wakeRecovery)
                }
            }
        }
    }

    private func cancelAllTasks() {
        closeDebounceTask?.cancel()
        startupCooldownTask?.cancel()
        wakeRecoveryTask?.cancel()
        closeDebounceTask = nil
        startupCooldownTask = nil
        wakeRecoveryTask = nil
    }
}
