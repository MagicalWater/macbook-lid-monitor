import Foundation
import XCTest
@testable import LidMonitorCore

final class ProductionDaemonCompositionTests: XCTestCase {
    func testDisabledModeDoesNotEnumerateOrCreateRequester() throws {
        let fixture = Fixture(mode: .disabled, descriptors: [])

        let result = try fixture.application.start()

        XCTAssertEqual(result, .disabled)
        XCTAssertEqual(fixture.enumerator.callCount, 0)
        XCTAssertTrue(fixture.requesterFactory.requestedModes.isEmpty)
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

    func testEnabledUnknownHardwareFailsBeforeRealRequesterConstruction() {
        let fixture = Fixture(mode: .enabled, descriptors: [])

        XCTAssertThrowsError(try fixture.application.start()) { error in
            XCTAssertEqual(error as? ProductionDaemonError, .incompatibleHardware)
        }
        XCTAssertTrue(fixture.requesterFactory.requestedModes.isEmpty)
        XCTAssertTrue(fixture.events.events.contains(.healthChanged(.incompatibleHardware)))
    }

    func testOpenCrashCircuitPreventsEnumerationAndRequesterConstruction() throws {
        let fixture = Fixture(mode: .enabled, descriptors: [Fixture.exactDescriptor], allowsStart: false)

        let result = try fixture.application.start()

        XCTAssertEqual(result, .circuitOpen)
        XCTAssertEqual(fixture.enumerator.callCount, 0)
        XCTAssertTrue(fixture.requesterFactory.requestedModes.isEmpty)
        XCTAssertTrue(fixture.events.events.contains(.healthChanged(.degradedFailOpen)))
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
    var unexpectedExitCount: Int { unexpectedExitCounter.value }
    var cleanExitCount: Int { cleanExitCounter.value }
    lazy var application = ProductionDaemonApplication(
        dependencies: ProductionDaemonDependencies(
            allowsStart: { [allowsStart] _ in allowsStart },
            recordUnexpectedExit: { [unexpectedExitCounter] _ in unexpectedExitCounter.increment() },
            recordCleanExit: { [cleanExitCounter] in cleanExitCounter.increment() },
            loadConfiguration: { [configuration] in configuration },
            enumerator: enumerator,
            registry: .production,
            streamFactory: { [stream] _ in stream },
            scheduler: scheduler,
            wakeObserver: wakeObserver,
            requesterFactory: requesterFactory.make,
            eventSink: events,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
    )

    private let allowsStart: Bool

    init(
        mode: ProductionMode,
        descriptors: [HIDDeviceDescriptor],
        allowsStart: Bool = true,
        streamStartError: Error? = nil
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
    func start(onReport: @escaping @Sendable (HIDReport) -> Void) throws {
        startCount += 1
        if let startError { throw startError }
    }
    func stop() { stopCount += 1 }
}

private final class CompositionWakeObserver: SystemWakeObserving, @unchecked Sendable {
    private var onWake: (@Sendable (Date) -> Void)?
    func start(onWake: @escaping @Sendable (Date) -> Void) throws { self.onWake = onWake }
    func stop() { onWake = nil }
    func triggerWake(at date: Date) { onWake?(date) }
}

private final class CompositionScheduler: OneShotScheduling, @unchecked Sendable {
    func schedule(at deadline: Date, _ action: @escaping @Sendable () -> Void) -> CancellableTask {
        CompositionTask()
    }
}

private final class CompositionTask: CancellableTask, @unchecked Sendable { func cancel() {} }
private final class CompositionRequester: SleepRequesting, @unchecked Sendable { func requestSleep() throws {} }

private final class CompositionRequesterFactory: @unchecked Sendable {
    private(set) var requestedModes: [ProductionMode] = []
    func make(_ mode: ProductionMode, _ sink: ProductionEventSinking) -> SleepRequesting {
        requestedModes.append(mode)
        return CompositionRequester()
    }
}

private final class CompositionEventSink: ProductionEventSinking, @unchecked Sendable {
    private(set) var events: [ProductionEvent] = []
    func emit(_ event: ProductionEvent) { events.append(event) }
}

private enum CompositionFailure: Error { case failed }

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
