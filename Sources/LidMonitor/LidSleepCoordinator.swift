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
    private let onTransitionEvent: @Sendable (AutoSleepTransitionEvent) -> Void
    private let queue = DispatchQueue(label: "macbook-lid-monitor.coordinator")

    private var machine: LidSleepStateMachine
    private var debounceTask: CancellableTask?
    private var cooldownTask: CancellableTask?
    private var lastReportedState: LidSleepState = .cooldown
    private var started = false

    init(
        stream: HIDReportStreaming,
        decoder: LidAngleDecoding,
        scheduler: OneShotScheduling,
        wakeObserver: SystemWakeObserving,
        sleepRequester: SleepRequesting,
        policy: LidSleepPolicy,
        now: @escaping @Sendable () -> Date = Date.init,
        onTransitionEvent: @escaping @Sendable (AutoSleepTransitionEvent) -> Void = { _ in }
    ) {
        self.stream = stream
        self.decoder = decoder
        self.scheduler = scheduler
        self.wakeObserver = wakeObserver
        self.sleepRequester = sleepRequester
        self.policy = policy
        self.now = now
        self.onTransitionEvent = onTransitionEvent
        machine = LidSleepStateMachine(policy: policy)
    }

    func start() throws {
        try queue.sync {
            guard !started else { return }
            started = true

            wakeObserver.start { [weak self] date in
                self?.queue.sync {
                    self?.handleWake(at: date)
                }
            }

            scheduleCooldown(from: now())

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
        apply(machine.handle(.systemDidWake(at: date)))
        cooldownTask?.cancel()
        cooldownTask = nil
        scheduleCooldown(from: date)
    }

    private func scheduleCooldown(from date: Date) {
        let deadline = date.addingTimeInterval(policy.startupCooldown)
        cooldownTask?.cancel()
        cooldownTask = scheduler.schedule(at: deadline) { [weak self] in
            self?.queue.sync {
                guard let self, self.started else { return }
                self.cooldownTask = nil
                self.apply(self.machine.handle(.cooldownElapsed(at: deadline)))
            }
        }
    }

    private func apply(_ effects: [LidSleepEffect]) {
        for effect in effects {
            switch effect {
            case let .scheduleDebounce(deadline):
                debounceTask?.cancel()
                debounceTask = scheduler.schedule(at: deadline) { [weak self] in
                    self?.queue.sync {
                        guard let self, self.started else { return }
                        self.debounceTask = nil
                        self.apply(self.machine.handle(.debounceElapsed(at: deadline)))
                    }
                }

            case .cancelDebounce:
                debounceTask?.cancel()
                debounceTask = nil

            case .requestSleep:
                try? sleepRequester.requestSleep()

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
                case .triggered: onTransitionEvent(.triggered)
                case .disarmed: onTransitionEvent(.disarmed)
                case .cooldown: onTransitionEvent(.cooldown)
                }
            }
        }
    }

    private func cancelAllTasks() {
        debounceTask?.cancel()
        cooldownTask?.cancel()
        debounceTask = nil
        cooldownTask = nil
    }
}
