import Foundation

enum ProductionDaemonError: Error, Equatable, Sendable {
    case incompatibleHardware
    case installedSetInvalid
    case sleepAuthorityUnavailable
    case unsupportedMode
}

struct ProductionDaemonDependencies {
    let beginRun: @Sendable (Date) throws -> Bool
    let recordUnexpectedExit: @Sendable (Date) throws -> Void
    let recordCleanExit: @Sendable () throws -> Void
    let loadConfiguration: @Sendable () throws -> ProductionConfiguration
    let verifyInstalledSet: @Sendable (ProductionMode) throws -> ProductionInstalledSetIdentity
    let enumerator: HIDDeviceEnumerating
    let registry: LidHardwareProfileRegistry
    let streamFactory: @Sendable (HIDDeviceDescriptor) throws -> HIDReportStreaming
    let scheduler: OneShotScheduling
    let wakeObserver: SystemWakeObserving
    let requesterFactory: @Sendable (ProductionMode, ProductionEventSinking) -> SleepRequesting
    let acquireSleepAuthority: @Sendable () throws -> SleepAuthorityHolding
    let eventSink: ProductionEventSinking
    let now: @Sendable () -> Date
}

final class ProductionDaemonSession: @unchecked Sendable {
    private let coordinator: LidSleepCoordinator
    private let sink: ProductionEventSinking
    private let recordCleanExit: @Sendable () throws -> Void
    private let sleepAuthority: SleepAuthorityHolding?
    private let lock = NSLock()
    private var stopped = false

    init(
        coordinator: LidSleepCoordinator,
        sink: ProductionEventSinking,
        sleepAuthority: SleepAuthorityHolding?,
        recordCleanExit: @escaping @Sendable () throws -> Void
    ) {
        self.coordinator = coordinator
        self.sink = sink
        self.sleepAuthority = sleepAuthority
        self.recordCleanExit = recordCleanExit
    }

    func stop(reason: String) {
        let shouldStop = lock.withLock { () -> Bool in
            guard !stopped else { return false }
            stopped = true
            return true
        }
        guard shouldStop else { return }
        sink.emit(.stopping(reason: reason))
        coordinator.stop()
        try? recordCleanExit()
    }
}

enum ProductionDaemonStartResult: Equatable {
    case disabled
    case circuitOpen
    case running(ProductionDaemonSession)

    static func == (lhs: ProductionDaemonStartResult, rhs: ProductionDaemonStartResult) -> Bool {
        switch (lhs, rhs) {
        case (.disabled, .disabled): return true
        case (.circuitOpen, .circuitOpen): return true
        case let (.running(a), .running(b)): return a === b
        default: return false
        }
    }
}

func productionDaemonImmediateExitCode(for result: ProductionDaemonStartResult) -> Int32? {
    switch result {
    case .disabled, .circuitOpen:
        return ExitCode.success.rawValue
    case .running:
        return nil
    }
}

final class ProductionDaemonApplication {
    private let dependencies: ProductionDaemonDependencies

    init(dependencies: ProductionDaemonDependencies) {
        self.dependencies = dependencies
    }

    func start() throws -> ProductionDaemonStartResult {
        guard try dependencies.beginRun(dependencies.now()) else {
            dependencies.eventSink.emit(.degraded(code: "crash-circuit-open"))
            dependencies.eventSink.emit(.healthChanged(.degradedFailOpen))
            return .circuitOpen
        }
        let configuration = try dependencies.loadConfiguration()
        dependencies.eventSink.emit(
            .started(mode: configuration.mode, profileID: configuration.hardwareProfileID)
        )
        guard configuration.mode != .disabled else {
            dependencies.eventSink.emit(.healthChanged(.disabled))
            try? dependencies.recordCleanExit()
            return .disabled
        }
        if configuration.mode == .enabled {
            do {
                _ = try dependencies.verifyInstalledSet(configuration.mode)
            } catch {
                dependencies.eventSink.emit(.degraded(code: "installed-set-invalid"))
                dependencies.eventSink.emit(.healthChanged(.degradedFailOpen))
                try? dependencies.recordCleanExit()
                throw ProductionDaemonError.installedSetInvalid
            }
        }

        let descriptors: [HIDDeviceDescriptor]
        do {
            descriptors = try dependencies.enumerator.descriptors()
        } catch {
            try? dependencies.recordUnexpectedExit(dependencies.now())
            throw error
        }
        let resolved: ResolvedLidHardwareProfile
        do {
            resolved = try dependencies.registry.resolve(
                profileID: configuration.hardwareProfileID,
                descriptors: descriptors
            )
        } catch {
            dependencies.eventSink.emit(.healthChanged(.incompatibleHardware))
            throw ProductionDaemonError.incompatibleHardware
        }

        let sleepAuthority: SleepAuthorityHolding?
        if configuration.mode == .enabled {
            do {
                sleepAuthority = try dependencies.acquireSleepAuthority()
            } catch {
                dependencies.eventSink.emit(.degraded(code: "sleep-authority-unavailable"))
                dependencies.eventSink.emit(.healthChanged(.degradedFailOpen))
                try? dependencies.recordCleanExit()
                throw ProductionDaemonError.sleepAuthorityUnavailable
            }
        } else {
            sleepAuthority = nil
        }
        let requester = dependencies.requesterFactory(configuration.mode, dependencies.eventSink)
        let sink = dependencies.eventSink
        let stream: HIDReportStreaming
        do {
            stream = try dependencies.streamFactory(resolved.descriptor)
        } catch {
            try? dependencies.recordUnexpectedExit(dependencies.now())
            throw error
        }
        let coordinator = LidSleepCoordinator(
            stream: stream,
            decoder: resolved.decoder,
            scheduler: dependencies.scheduler,
            wakeObserver: dependencies.wakeObserver,
            sleepRequester: requester,
            policy: configuration.policy,
            maximumSampleAge: configuration.sensorFreshness,
            now: dependencies.now,
            onOperationalEvent: { event in
                switch event {
                case .sleepRequestAttempted: sink.emit(.transition(name: "sleep-request-attempted"))
                case let .sleepRequestFailed(code): sink.emit(.degraded(code: code))
                case .wouldSleep:
                    sink.emit(.transition(name: "would-sleep"))
                    sink.emit(.healthChanged(.dryRun))
                case .sleepRequested: sink.emit(.sleepRequested)
                }
            },
            onTransitionEvent: { event in
                switch event {
                case .rearmed:
                    sink.emit(.transition(name: "monitoring-armed"))
                    sink.emit(.stateChanged(.monitoringArmed, sensorValue: nil))
                case .disarmed, .recoverySensorUnavailable, .wakeRecovery:
                    sink.emit(.stateChanged(.monitoringDisarmed, sensorValue: nil))
                case .candidateStarted: sink.emit(.transition(name: "candidate-started"))
                case .candidateCancelled: sink.emit(.transition(name: "candidate-cancelled"))
                case .triggered: sink.emit(.transition(name: "debounce-elapsed"))
                case .recoveryResleep: sink.emit(.transition(name: "recovery-resleep"))
                case .startupCooldown: sink.emit(.transition(name: "startup-cooldown"))
                }
            }
        )
        do {
            try coordinator.start()
        } catch {
            try? dependencies.recordUnexpectedExit(dependencies.now())
            throw error
        }
        dependencies.eventSink.emit(
            .healthChanged(configuration.mode == .dryRun ? .dryRun : .monitoringDisarmed)
        )
        return .running(
            ProductionDaemonSession(
                coordinator: coordinator,
                sink: dependencies.eventSink,
                sleepAuthority: sleepAuthority,
                recordCleanExit: dependencies.recordCleanExit
            )
        )
    }
}

public enum LidMonitorProductionDaemonEntryPoint {
    public static func run(arguments: [String]) -> Int32 {
        guard arguments.isEmpty else { return ExitCode.usage.rawValue }
        let sink = ProductionEventSink()
        let dependencies = ProductionDaemonDependencies(
            beginRun: { date in
                var budget = CrashBudget(
                    storage: FileCrashBudgetStorage(),
                    maximumUnexpectedExits: 3,
                    window: 300
                )
                return try budget.beginRun(at: date)
            },
            recordUnexpectedExit: { date in
                var budget = CrashBudget(
                    storage: FileCrashBudgetStorage(),
                    maximumUnexpectedExits: 3,
                    window: 300
                )
                _ = try budget.recordUnexpectedExit(at: date)
            },
            recordCleanExit: {
                var budget = CrashBudget(
                    storage: FileCrashBudgetStorage(),
                    maximumUnexpectedExits: 3,
                    window: 300
                )
                try budget.recordCleanExit()
            },
            loadConfiguration: { try ProductionConfigurationLoader().load() },
            verifyInstalledSet: { try ProductionInstalledSetVerifier().verify(mode: $0) },
            enumerator: IOHIDDeviceEnumerator(),
            registry: .production,
            streamFactory: { try IOHIDReportStream(descriptor: $0) },
            scheduler: DispatchOneShotScheduler(),
            wakeObserver: IOKitSystemWakeObserver(),
            requesterFactory: { mode, sink in
                switch mode {
                case .dryRun:
                    return DryRunSleepRequester { event in
                        if case .wouldSleep = event {
                            sink.emit(.transition(name: "would-sleep"))
                            sink.emit(.healthChanged(.dryRun))
                        }
                    }
                case .enabled:
                    return MacOSSleepRequester(
                        operation: IOKitSystemSleepOperation(),
                        onEvent: { event in
                            if case .sleepRequested = event {
                                sink.emit(.sleepRequested)
                            } else if case let .sleepRequestFailed(code) = event {
                                sink.emit(.degraded(code: code))
                            }
                        }
                    )
                case .disabled:
                    return DryRunSleepRequester { _ in }
                }
            },
            acquireSleepAuthority: {
                let resolver = SleepAuthorityPathResolver()
                let lease = try resolver.makeLease(
                    markers: resolver.currentMarkers()
                )
                return try lease.acquire()
            },
            eventSink: sink,
            now: Date.init
        )
        do {
            let result = try ProductionDaemonApplication(dependencies: dependencies).start()
            if let exitCode = productionDaemonImmediateExitCode(for: result) {
                return exitCode
            }
            switch result {
            case .disabled, .circuitOpen:
                preconditionFailure("immediate result must have an exit code")
            case let .running(session):
                let finished = DispatchSemaphore(value: 0)
                let signals = ProcessSignalController()
                try signals.start {
                    session.stop(reason: "signal")
                    finished.signal()
                }
                finished.wait()
                signals.stop()
                return ExitCode.success.rawValue
            }
        } catch is ProductionConfigurationError {
            return ExitCode.usage.rawValue
        } catch ProductionDaemonError.incompatibleHardware {
            return ExitCode.unavailable.rawValue
        } catch ProductionDaemonError.installedSetInvalid {
            return ExitCode.success.rawValue
        } catch ProductionDaemonError.sleepAuthorityUnavailable {
            return ExitCode.success.rawValue
        } catch is HIDReportStreamError {
            return ExitCode.ioFailure.rawValue
        } catch {
            return ExitCode.internalError.rawValue
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
