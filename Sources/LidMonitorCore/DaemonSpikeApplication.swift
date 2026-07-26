import Foundation

enum DaemonSpikeError: Error, Equatable {
    case candidateUnavailable
}

struct DaemonSpikeDependencies {
    let enumerator: HIDDeviceEnumerating
    let streamFactory: (HIDDeviceDescriptor) throws -> HIDReportStreaming
    let decoder: LidAngleDecoding
    let scheduler: OneShotScheduling
    let wakeObserver: SystemWakeObserving
    let evidenceSink: DaemonSpikeEvidenceSinking
    let now: @Sendable () -> Date
}

final class DaemonSpikeSession: @unchecked Sendable {
    private let lock = NSLock()
    private let coordinator: LidSleepCoordinator
    private let evidenceSink: DaemonSpikeEvidenceSinking
    private var stopped = false

    init(coordinator: LidSleepCoordinator, evidenceSink: DaemonSpikeEvidenceSinking) {
        self.coordinator = coordinator
        self.evidenceSink = evidenceSink
    }

    func stop(reason: String) {
        let shouldStop = lock.withLock { () -> Bool in
            guard !stopped else { return false }
            stopped = true
            return true
        }
        guard shouldStop else { return }
        evidenceSink.emit(.stopping(reason: reason))
        coordinator.stop()
    }
}

final class DaemonSpikeApplication {
    private let dependencies: DaemonSpikeDependencies

    init(dependencies: DaemonSpikeDependencies) {
        self.dependencies = dependencies
    }

    func start() throws -> DaemonSpikeSession {
        dependencies.evidenceSink.emit(.runtimeStarted(.current()))
        let ranked = CandidateRanker.rank(try dependencies.enumerator.descriptors())
        guard let selected = ranked.first,
              selected.score >= CandidateRanker.minimumSelectableScore else {
            dependencies.evidenceSink.emit(.candidateUnavailable)
            throw DaemonSpikeError.candidateUnavailable
        }
        dependencies.evidenceSink.emit(.candidateSelected(selected.descriptor, score: selected.score))

        let stream: HIDReportStreaming
        do {
            stream = try dependencies.streamFactory(selected.descriptor)
        } catch {
            dependencies.evidenceSink.emit(.streamStartFailed)
            throw error
        }
        let requester = DryRunSleepRequester { _ in }
        let evidenceSink = dependencies.evidenceSink
        let formatter = OutputFormatter()
        let recorder = DaemonSpikeReportRecorder(sink: evidenceSink)
        let coordinator = LidSleepCoordinator(
            stream: stream,
            decoder: EvidenceRecordingLidAngleDecoder(base: dependencies.decoder, recorder: recorder),
            scheduler: dependencies.scheduler,
            wakeObserver: dependencies.wakeObserver,
            sleepRequester: requester,
            policy: .calibratedDefault,
            now: dependencies.now,
            onOperationalEvent: { event in
                evidenceSink.emitPolicyLine(formatter.autoSleepLine(event))
            },
            onTransitionEvent: { event in
                evidenceSink.emitPolicyLine(formatter.autoSleepTransitionLine(event))
            }
        )
        do {
            try coordinator.start()
            dependencies.evidenceSink.emit(.hidOpened(registryID: selected.descriptor.registryEntryID))
        } catch let error as SystemPowerNotificationError {
            dependencies.evidenceSink.emit(
                .powerObserverRegistrationFailed(String(describing: error))
            )
            throw error
        } catch let error as HIDReportStreamError {
            if case let .openFailed(code) = error {
                dependencies.evidenceSink.emit(.hidOpenFailed(registryID: selected.descriptor.registryEntryID, code: code))
            } else {
                dependencies.evidenceSink.emit(.streamStartFailed)
            }
            throw error
        } catch {
            dependencies.evidenceSink.emit(.streamStartFailed)
            throw error
        }
        return DaemonSpikeSession(coordinator: coordinator, evidenceSink: dependencies.evidenceSink)
    }
}

public enum LidMonitorDaemonSpikeEntryPoint {
    public static func run(arguments: [String]) -> Int32 {
        guard arguments.isEmpty else { return ExitCode.usage.rawValue }
        let sink = StandardDaemonEvidenceSink()
        let dependencies = DaemonSpikeDependencies(
            enumerator: IOHIDDeviceEnumerator(),
            streamFactory: { try IOHIDReportStream(descriptor: $0) },
            decoder: CompositeLidAngleDecoder(
                decoders: [ReportID1DegreesDecoder(), UInt16TenthsDecoder()]
            ),
            scheduler: DispatchOneShotScheduler(),
            wakeObserver: IOKitSystemWakeObserver(
                onPowerEvent: { event in sink.emit(.power(event)) },
                onRegistered: { sink.emit(.powerObserverRegistered) }
            ),
            evidenceSink: sink,
            now: Date.init
        )
        do {
            let session = try DaemonSpikeApplication(dependencies: dependencies).start()
            let finished = DispatchSemaphore(value: 0)
            let signals = ProcessSignalController()
            do {
                try signals.start {
                    session.stop(reason: "signal")
                    finished.signal()
                }
            } catch {
                session.stop(reason: "signal-controller-start-failed")
                throw error
            }
            finished.wait()
            signals.stop()
            return ExitCode.success.rawValue
        } catch DaemonSpikeError.candidateUnavailable {
            return ExitCode.unavailable.rawValue
        } catch is HIDReportStreamError {
            return ExitCode.ioFailure.rawValue
        } catch is HIDEnumerationError {
            return ExitCode.unavailable.rawValue
        } catch {
            return ExitCode.internalError.rawValue
        }
    }
}
