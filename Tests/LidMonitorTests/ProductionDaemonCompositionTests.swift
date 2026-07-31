import Foundation
import XCTest
@testable import LidMonitorCore

final class ProductionDaemonCompositionTests: XCTestCase {
    func testInvalidInstalledSetFailsOpenBeforeRequesterConstruction() throws {
        let fixture = Fixture(
            mode: .enabled,
            descriptors: [Fixture.exactDescriptor],
            installedSetError: CompositionFailure.failed
        )

        XCTAssertThrowsError(try fixture.application.start()) { error in
            XCTAssertEqual(error as? ProductionDaemonError, .installedSetInvalid)
        }
        XCTAssertTrue(fixture.requesterFactory.requestedModes.isEmpty)
        XCTAssertTrue(fixture.events.events.contains(.degraded(code: "installed-set-invalid")))
        XCTAssertEqual(fixture.cleanExitCount, 1)
    }
    func testDeployableProductionSourceContainsNoSleepOperationEnvironmentOverride() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/LidMonitorCore/Production/ProductionDaemonApplication.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(source.contains("MLM_SLEEP_OPERATION"))
        XCTAssertFalse(source.contains("ProcessInfo.processInfo.environment"))
        XCTAssertTrue(source.contains("operation: IOKitSystemSleepOperation()"))
    }
    func testDisabledModeDoesNotEnumerateOrCreateRequester() throws {
        let fixture = Fixture(mode: .disabled, descriptors: [])

        let result = try fixture.application.start()

        XCTAssertEqual(result, .disabled)
        XCTAssertEqual(fixture.enumerator.callCount, 0)
        XCTAssertTrue(fixture.requesterFactory.requestedModes.isEmpty)
        XCTAssertEqual(fixture.beginRunCount, 1)
        XCTAssertEqual(fixture.cleanExitCount, 1)
        XCTAssertEqual(fixture.events.events, [
            .started(mode: .disabled, profileID: fixture.configuration.hardwareProfileID),
            .healthChanged(.disabled),
        ])
    }

    func testDryRunUsesDryRunRequesterAndStartsExactProfile() throws {
        let fixture = Fixture(mode: .dryRun, descriptors: [Fixture.exactDescriptor])

        let result = try fixture.application.start()

        guard case let .running(session) = result else {
            return XCTFail("expected running session")
        }
        XCTAssertEqual(fixture.requesterFactory.requestedModes, [.dryRun])
        XCTAssertEqual(fixture.stream.startCount, 1)
        session.stop(reason: "test")
        session.stop(reason: "duplicate")
        XCTAssertEqual(fixture.stream.stopCount, 1)
    }

    func testWakeTransitionEmitsProductionRecoveryEvidence() throws {
        let fixture = Fixture(mode: .dryRun, descriptors: [Fixture.exactDescriptor])

        let result = try fixture.application.start()
        guard case let .running(session) = result else {
            return XCTFail("expected running session")
        }
        fixture.wakeObserver.triggerWake(at: Date(timeIntervalSince1970: 1_001))
        XCTAssertTrue(fixture.events.events.contains(.stateChanged(.monitoringDisarmed, sensorValue: nil)))
        session.stop(reason: "test")
    }

    func testDryRunClosePathEmitsDiagnosticTransitions() throws {
        let fixture = Fixture(mode: .dryRun, descriptors: [Fixture.exactDescriptor])

        let result = try fixture.application.start()
        guard case let .running(session) = result else {
            return XCTFail("expected running session")
        }

        fixture.scheduler.runAll()
        fixture.stream.emit(report: [1, 90, 0], at: Date(timeIntervalSince1970: 1_010))
        fixture.stream.emit(report: [1, 60, 0], at: Date(timeIntervalSince1970: 1_011))
        fixture.scheduler.runAll()

        XCTAssertTrue(fixture.events.events.contains(.transition(name: "candidate-started")))
        XCTAssertTrue(fixture.events.events.contains(.transition(name: "debounce-elapsed")))
        XCTAssertTrue(fixture.events.events.contains(.transition(name: "sleep-request-attempted")))
        XCTAssertTrue(fixture.events.events.contains(.transition(name: "would-sleep")))
        session.stop(reason: "test")
    }

    func testDryRunClosedStartupEmitsStartupTransitions() throws {
        let fixture = Fixture(mode: .dryRun, descriptors: [Fixture.exactDescriptor])

        let result = try fixture.application.start()
        guard case let .running(session) = result else {
            return XCTFail("expected running session")
        }

        fixture.stream.emit(report: [1, 60, 0], at: Date(timeIntervalSince1970: 1_001))
        fixture.scheduler.runAll()
        fixture.stream.emit(report: [1, 60, 0], at: Date(timeIntervalSince1970: 1_006))
        fixture.scheduler.runAll()

        XCTAssertTrue(
            fixture.events.events.contains(.transition(name: "startup-closed-candidate"))
        )
        XCTAssertTrue(
            fixture.events.events.contains(.transition(name: "startup-closed-debounce-elapsed"))
        )
        XCTAssertTrue(fixture.events.events.contains(.transition(name: "sleep-request-attempted")))
        XCTAssertTrue(fixture.events.events.contains(.transition(name: "would-sleep")))
        session.stop(reason: "test")
    }

    func testEnabledClosedStartupRequestsProductionRequesterOnce() throws {
        let fixture = Fixture(mode: .enabled, descriptors: [Fixture.exactDescriptor])

        let result = try fixture.application.start()
        guard case let .running(session) = result else {
            return XCTFail("expected running session")
        }

        fixture.stream.emit(report: [1, 60, 0], at: Date(timeIntervalSince1970: 1_001))
        fixture.scheduler.runAll()
        fixture.stream.emit(report: [1, 60, 0], at: Date(timeIntervalSince1970: 1_006))
        fixture.scheduler.runAll()

        XCTAssertEqual(fixture.requesterFactory.requestCount, 1)
        XCTAssertTrue(
            fixture.events.events.contains(.transition(name: "startup-closed-candidate"))
        )
        XCTAssertTrue(
            fixture.events.events.contains(.transition(name: "startup-closed-debounce-elapsed"))
        )
        XCTAssertTrue(fixture.events.events.contains(.transition(name: "sleep-request-attempted")))
        session.stop(reason: "test")
    }

    func testOnlyValidDecodedReportsRecordHealthSamples() throws {
        let fixture = Fixture(mode: .dryRun, descriptors: [Fixture.exactDescriptor])
        let result = try fixture.application.start()
        guard case let .running(session) = result else {
            return XCTFail("expected running session")
        }

        fixture.stream.emit(report: [], at: Date(timeIntervalSince1970: 1_009))
        fixture.stream.emit(report: [1, 90, 0], at: Date(timeIntervalSince1970: 1_010))

        XCTAssertEqual(fixture.validSampleCount, 1)
        session.stop(reason: "test")
    }

    func testEnabledUnknownHardwareFailsBeforeRealRequesterConstruction() {
        let fixture = Fixture(mode: .enabled, descriptors: [])

        XCTAssertThrowsError(try fixture.application.start()) { error in
            XCTAssertEqual(error as? ProductionDaemonError, .incompatibleHardware)
        }
        XCTAssertTrue(fixture.requesterFactory.requestedModes.isEmpty)
        XCTAssertTrue(fixture.events.events.contains(.healthChanged(.incompatibleHardware)))
    }

    func testEnabledAuthorityConflictFailsOpenBeforeRequesterConstruction() {
        let fixture = Fixture(
            mode: .enabled,
            descriptors: [Fixture.exactDescriptor],
            authorityError: SleepAuthorityLeaseError.alreadyHeld
        )

        XCTAssertThrowsError(try fixture.application.start()) { error in
            XCTAssertEqual(error as? ProductionDaemonError, .sleepAuthorityUnavailable)
        }
        XCTAssertTrue(fixture.requesterFactory.requestedModes.isEmpty)
        XCTAssertTrue(fixture.events.events.contains(.degraded(code: "sleep-authority-unavailable")))
        XCTAssertEqual(fixture.cleanExitCount, 1)
    }

    func testOpenCrashCircuitPreventsEnumerationAndRequesterConstruction() throws {
        let fixture = Fixture(mode: .enabled, descriptors: [Fixture.exactDescriptor], allowsStart: false)

        let result = try fixture.application.start()

        XCTAssertEqual(result, .circuitOpen)
        XCTAssertEqual(fixture.enumerator.callCount, 0)
        XCTAssertTrue(fixture.requesterFactory.requestedModes.isEmpty)
        XCTAssertTrue(fixture.events.events.contains(.healthChanged(.degradedFailOpen)))
        XCTAssertEqual(productionDaemonImmediateExitCode(for: result), ExitCode.success.rawValue)
    }

    func testUnexpectedStreamStartupFailureConsumesCrashBudget() {
        let fixture = Fixture(
            mode: .dryRun,
            descriptors: [Fixture.exactDescriptor],
            streamStartError: CompositionFailure.failed
        )

        XCTAssertThrowsError(try fixture.application.start())
        XCTAssertEqual(fixture.unexpectedExitCount, 1)
        XCTAssertEqual(fixture.cleanExitCount, 0)
    }
}

private final class Fixture {
    static let exactDescriptor = HIDDeviceDescriptor(
        registryEntryID: 1,
        name: "Apple Hinge Orientation Sensor",
        vendorID: 0x05AC,
        productID: 0x8104,
        usagePage: 0x0020,
        usage: 0x008A,
        transport: "SPU",
        inputClass: .other
    )

    let configuration: ProductionConfiguration
    let enumerator: CompositionEnumerator
    let stream = CompositionStream()
    let wakeObserver = CompositionWakeObserver()
    let scheduler = CompositionScheduler()
    let requesterFactory = CompositionRequesterFactory()
    let events = CompositionEventSink()
    private let unexpectedExitCounter = CompositionCounter()
    private let cleanExitCounter = CompositionCounter()
    private let beginRunCounter = CompositionCounter()
    private let validSampleCounter = CompositionCounter()
    var unexpectedExitCount: Int { unexpectedExitCounter.value }
    var cleanExitCount: Int { cleanExitCounter.value }
    var beginRunCount: Int { beginRunCounter.value }
    var validSampleCount: Int { validSampleCounter.value }
    lazy var application = ProductionDaemonApplication(
        dependencies: ProductionDaemonDependencies(
            beginRun: { [allowsStart, beginRunCounter] _ in
                beginRunCounter.increment()
                return allowsStart
            },
            recordUnexpectedExit: { [unexpectedExitCounter] _ in unexpectedExitCounter.increment() },
            recordCleanExit: { [cleanExitCounter] in cleanExitCounter.increment() },
            loadConfiguration: { [configuration] in configuration },
            verifyInstalledSet: { [installedSetError, configuration] mode in
                if let installedSetError { throw installedSetError }
                return ProductionInstalledSetIdentity(
                    sourceCommit: "commit", manifestSHA256: "manifest", binarySHA256: "binary",
                    plistSHA256: "plist", normalizedConfigSHA256: "normalized",
                    currentConfigSHA256: "current", hardwareProfileID: configuration.hardwareProfileID
                )
            },
            enumerator: enumerator,
            registry: .production,
            streamFactory: { [stream] _ in stream },
            scheduler: scheduler,
            wakeObserver: wakeObserver,
            requesterFactory: requesterFactory.make,
            acquireSleepAuthority: { [authorityError] in
                if let authorityError { throw authorityError }
                return CompositionAuthorityHolding()
            },
            recordValidSample: { [validSampleCounter] _ in validSampleCounter.increment() },
            eventSink: events,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
    )

    private let allowsStart: Bool
    private let authorityError: Error?
    private let installedSetError: Error?

    init(
        mode: ProductionMode,
        descriptors: [HIDDeviceDescriptor],
        allowsStart: Bool = true,
        streamStartError: Error? = nil,
        authorityError: Error? = nil,
        installedSetError: Error? = nil
    ) {
        configuration = ProductionConfiguration(
            schemaVersion: 1,
            mode: mode,
            hardwareProfileID: "m1-pro-0x8104-report-id-1-v1",
            policy: .calibratedDefault,
            sensorFreshness: 5
        )
        enumerator = CompositionEnumerator(descriptors: descriptors)
        self.allowsStart = allowsStart
        self.authorityError = authorityError
        self.installedSetError = installedSetError
        stream.startError = streamStartError
    }
}

private final class CompositionEnumerator: HIDDeviceEnumerating {
    let values: [HIDDeviceDescriptor]
    private(set) var callCount = 0
    init(descriptors: [HIDDeviceDescriptor]) { values = descriptors }
    func descriptors() throws -> [HIDDeviceDescriptor] { callCount += 1; return values }
}

private final class CompositionStream: HIDReportStreaming, @unchecked Sendable {
    var startError: Error?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var onReport: (@Sendable (HIDReport) -> Void)?
    func start(onReport: @escaping @Sendable (HIDReport) -> Void) throws {
        startCount += 1
        if let startError { throw startError }
        self.onReport = onReport
    }
    func stop() { stopCount += 1; onReport = nil }
    func emit(report: [UInt8], at date: Date) {
        onReport?(HIDReport(reportID: 1, bytes: report, timestamp: date))
    }
}

private final class CompositionWakeObserver: SystemWakeObserving, @unchecked Sendable {
    private var onWake: (@Sendable (Date) -> Void)?
    func start(onWake: @escaping @Sendable (Date) -> Void) throws { self.onWake = onWake }
    func stop() { onWake = nil }
    func triggerWake(at date: Date) { onWake?(date) }
}

private final class CompositionScheduler: OneShotScheduling, @unchecked Sendable {
    private var actions: [@Sendable () -> Void] = []
    func schedule(at deadline: Date, _ action: @escaping @Sendable () -> Void) -> CancellableTask {
        actions.append(action)
        return CompositionTask()
    }
    func runAll() {
        let pending = actions
        actions.removeAll()
        pending.forEach { $0() }
    }
}

private final class CompositionTask: CancellableTask, @unchecked Sendable { func cancel() {} }
private final class CompositionRequesterFactory: @unchecked Sendable {
    private(set) var requestedModes: [ProductionMode] = []
    private let requestCounter = CompositionCounter()
    var requestCount: Int { requestCounter.value }
    func make(_ mode: ProductionMode, _ sink: ProductionEventSinking) -> SleepRequesting {
        requestedModes.append(mode)
        switch mode {
        case .dryRun:
            return DryRunSleepRequester { event in
                if case .wouldSleep = event {
                    sink.emit(.transition(name: "would-sleep"))
                }
            }
        case .enabled, .disabled:
            return CountingCompositionRequester(counter: requestCounter)
        }
    }
}

private final class CountingCompositionRequester: SleepRequesting, @unchecked Sendable {
    private let counter: CompositionCounter
    init(counter: CompositionCounter) { self.counter = counter }
    func requestSleep() throws { counter.increment() }
}

private final class CompositionEventSink: ProductionEventSinking, @unchecked Sendable {
    private(set) var events: [ProductionEvent] = []
    func emit(_ event: ProductionEvent) { events.append(event) }
}

private enum CompositionFailure: Error { case failed }
private final class CompositionAuthorityHolding: SleepAuthorityHolding, @unchecked Sendable {}

private final class CompositionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
