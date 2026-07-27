import Foundation

enum ProductionDaemonError: Error, Equatable, Sendable {
    case incompatibleHardware
    case unsupportedMode
}

struct ProductionDaemonDependencies {
    let allowsStart: @Sendable (Date) throws -> Bool
    let recordUnexpectedExit: @Sendable (Date) throws -> Void
    let recordCleanExit: @Sendable () throws -> Void
    let loadConfiguration: @Sendable () throws -> ProductionConfiguration
    let enumerator: HIDDeviceEnumerating
    let registry: LidHardwareProfileRegistry
    let streamFactory: @Sendable (HIDDeviceDescriptor) throws -> HIDReportStreaming
    let scheduler: OneShotScheduling
    let wakeObserver: SystemWakeObserving
    let requesterFactory: @Sendable (ProductionMode, ProductionEventSinking) -> SleepRequesting
    let eventSink: ProductionEventSinking
    let now: @Sendable () -> Date
}

final class ProductionDaemonSession: @unchecked Sendable {
    private let coordinator: LidSleepCoordinator
    private let sink: ProductionEventSinking
    private let recordCleanExit: @Sendable () throws -> Void
    private let lock = NSLock()
    private var stopped = false

    init(
        coordinator: LidSleepCoordinator,
        sink: ProductionEventSinking,
        recordCleanExit: @escaping @Sendable () throws -> Void
    ) {
        self.coordinator = coordinator
        self.sink = sink
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

final class ProductionDaemonApplication {
    private let dependencies: ProductionDaemonDependencies

    init(dependencies: ProductionDaemonDependencies) {
        self.dependencies = dependencies
    }

    func start() throws -> ProductionDaemonStartResult {
        guard try dependencies.allowsStart(dependencies.now()) else {
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
            return .disabled
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
                case let .sleepRequestFailed(code): sink.emit(.degraded(code: code))
                case .wouldSleep: sink.emit(.healthChanged(.dryRun))
                case .sleepRequested: break
                }
            },
            onTransitionEvent: { event in
                switch event {
                case .rearmed: sink.emit(.stateChanged(.monitoringArmed, sensorValue: nil))
                case .disarmed, .recoverySensorUnavailable, .wakeRecovery:
                    sink.emit(.stateChanged(.monitoringDisarmed, sensorValue: nil))
                default: break
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
            allowsStart: { date in
                var budget = CrashBudget(
                    storage: FileCrashBudgetStorage(),
                    maximumUnexpectedExits: 3,
                    window: 300
                )
                return try budget.allowsStart(at: date)
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
            enumerator: IOHIDDeviceEnumerator(),
            registry: .production,
            streamFactory: { try IOHIDReportStream(descriptor: $0) },
            scheduler: DispatchOneShotScheduler(),
            wakeObserver: IOKitSystemWakeObserver(),
            requesterFactory: { mode, sink in
                switch mode {
                case .dryRun:
                    return DryRunSleepRequester { _ in sink.emit(.healthChanged(.dryRun)) }
                case .enabled:
                    return MacOSSleepRequester(
                        operation: IOKitSystemSleepOperation(),
                        onEvent: { event in
                            if case let .sleepRequestFailed(code) = event {
                                sink.emit(.degraded(code: code))
                            }
                        }
                    )
                case .disabled:
                    return DryRunSleepRequester { _ in }
                }
            },
            eventSink: sink,
            now: Date.init
        )
        do {
            switch try ProductionDaemonApplication(dependencies: dependencies).start() {
            case .disabled:
                return ExitCode.success.rawValue
            case .circuitOpen:
                return ExitCode.unavailable.rawValue
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
