import XCTest
@testable import LidMonitorCore

final class DaemonSpikeCompositionTests: XCTestCase {
    func testStartEnumeratesSelectsStartsStreamAndWakeObserver() throws {
        let fixture = DaemonFixture()
        let session = try fixture.application.start()

        XCTAssertEqual(fixture.enumerator.callCount, 1)
        XCTAssertEqual(fixture.streamFactory.callCount, 1)
        XCTAssertEqual(fixture.stream.startCount, 1)
        XCTAssertEqual(fixture.wakeObserver.startCount, 1)
        XCTAssertEqual(Array(fixture.events.prefix(2)), [.runtimeStarted, .candidateSelected])

        session.stop(reason: "test")
        XCTAssertEqual(fixture.stream.stopCount, 1)
        XCTAssertEqual(fixture.wakeObserver.stopCount, 1)
    }

    func testNoCandidateReturnsUnavailableAndEvidence() {
        let fixture = DaemonFixture(descriptors: [])

        XCTAssertThrowsError(try fixture.application.start()) { error in
            XCTAssertEqual(error as? DaemonSpikeError, .candidateUnavailable)
        }
        XCTAssertEqual(fixture.events, [.runtimeStarted, .candidateUnavailable])
        XCTAssertEqual(fixture.streamFactory.callCount, 0)
    }

    func testStreamFailureReturnsIOFailureEvidence() {
        let fixture = DaemonFixture()
        fixture.stream.startError = HIDReportStreamError.openFailed(-1)

        XCTAssertThrowsError(try fixture.application.start())
        XCTAssertEqual(fixture.events.last, .streamStartFailed)
        XCTAssertEqual(fixture.wakeObserver.stopCount, 1)
    }

    func testStreamFactoryFailureEmitsFailureEvidence() {
        let fixture = DaemonFixture()
        fixture.streamFactory.makeError = HIDReportStreamError.deviceNotFound(1)

        XCTAssertThrowsError(try fixture.application.start())
        XCTAssertEqual(fixture.events.last, .streamStartFailed)
        XCTAssertEqual(fixture.wakeObserver.startCount, 0)
    }

    func testStopTwiceCleansUpOnce() throws {
        let fixture = DaemonFixture()
        let session = try fixture.application.start()
        session.stop(reason: "first")
        session.stop(reason: "second")

        XCTAssertEqual(fixture.stream.stopCount, 1)
        XCTAssertEqual(fixture.wakeObserver.stopCount, 1)
        XCTAssertEqual(fixture.events.filter { $0 == .stopping }.count, 1)
    }

    func testProductionCompositionHasNoRealSleepModeDependency() {
        let fixture = DaemonFixture()
        _ = fixture.application
        XCTAssertFalse(Mirror(reflecting: fixture.dependencies).children.contains { $0.label?.contains("sleep") == true })
    }
    func testEntryPointRejectsArgumentsBeforeStartup() {
        XCTAssertEqual(
            LidMonitorDaemonSpikeEntryPoint.run(arguments: ["--execute-sleep"]),
            ExitCode.usage.rawValue
        )
    }

}

private final class DaemonFixture {
    let enumerator: DaemonEnumerator
    let stream = DaemonStream()
    let streamFactory: DaemonStreamFactory
    let wakeObserver = DaemonWakeObserver()
    let evidence = DaemonEvidenceSink()
    let dependencies: DaemonSpikeDependencies
    let application: DaemonSpikeApplication

    var events: [DaemonSpikeEvidenceEvent] { evidence.events }

    init(descriptors: [HIDDeviceDescriptor]? = nil) {
        enumerator = DaemonEnumerator(descriptors: descriptors ?? [Self.sensor])
        streamFactory = DaemonStreamFactory(stream: stream)
        dependencies = DaemonSpikeDependencies(
            enumerator: enumerator,
            streamFactory: { [streamFactory] descriptor in try streamFactory.make(descriptor) },
            decoder: CompositeLidAngleDecoder(decoders: [ReportID1DegreesDecoder()]),
            scheduler: DaemonScheduler(),
            wakeObserver: wakeObserver,
            evidenceSink: evidence,
            now: { Date(timeIntervalSince1970: 1) }
        )
        application = DaemonSpikeApplication(dependencies: dependencies)
    }

    static let sensor = HIDDeviceDescriptor(
        registryEntryID: 1,
        name: "Apple",
        vendorID: 0x05AC,
        productID: 0x8104,
        usagePage: 0x20,
        usage: 0x8A,
        transport: "SPU",
        inputClass: .other
    )
}

private final class DaemonEnumerator: HIDDeviceEnumerating {
    let descriptorsValue: [HIDDeviceDescriptor]
    var callCount = 0
    init(descriptors: [HIDDeviceDescriptor]) { descriptorsValue = descriptors }
    func descriptors() throws -> [HIDDeviceDescriptor] { callCount += 1; return descriptorsValue }
}

private final class DaemonStreamFactory {
    let stream: DaemonStream
    var callCount = 0
    var makeError: Error?
    init(stream: DaemonStream) { self.stream = stream }
    func make(_ descriptor: HIDDeviceDescriptor) throws -> HIDReportStreaming {
        callCount += 1
        if let makeError { throw makeError }
        return stream
    }
}

private final class DaemonStream: HIDReportStreaming {
    var startCount = 0
    var stopCount = 0
    var startError: Error?
    func start(onReport: @escaping @Sendable (HIDReport) -> Void) throws { startCount += 1; if let startError { throw startError } }
    func stop() { stopCount += 1 }
}

private final class DaemonWakeObserver: SystemWakeObserving, @unchecked Sendable {
    var startCount = 0
    var stopCount = 0
    func start(onWake: @escaping @Sendable (Date) -> Void) throws { startCount += 1 }
    func stop() { stopCount += 1 }
}

private final class DaemonScheduler: OneShotScheduling, @unchecked Sendable {
    func schedule(at deadline: Date, _ action: @escaping @Sendable () -> Void) -> CancellableTask { DaemonTask() }
}
private final class DaemonTask: CancellableTask, @unchecked Sendable { func cancel() {} }

private final class DaemonEvidenceSink: DaemonSpikeEvidenceSinking, @unchecked Sendable {
    var events: [DaemonSpikeEvidenceEvent] = []
    func emit(_ event: DaemonSpikeEvidenceEvent) { events.append(event) }
}
