import Foundation
import XCTest
@testable import LidMonitorCore

final class AutoSleepIntegrationTests: XCTestCase {
    func testDryRunCompositionProcessesCalibratedCloseCycleEndToEnd() throws {
        let base = Date(timeIntervalSince1970: 3_000)
        let policy = LidSleepPolicy.calibratedDefault
        let stream = IntegrationReportStream()
        let scheduler = IntegrationScheduler()
        let wakeObserver = IntegrationWakeObserver()
        let recorder = IntegrationEventRecorder()

        let coordinator = AutoSleepComposition.makeCoordinator(
            stream: stream,
            decoder: CompositeLidAngleDecoder(decoders: [ReportID1DegreesDecoder()]),
            scheduler: scheduler,
            wakeObserver: wakeObserver,
            executionMode: .dryRun,
            policy: policy,
            now: { base },
            onOperationalEvent: recorder.record,
            onTransitionEvent: recorder.recordTransition
        )

        try coordinator.start()
        scheduler.fire(at: base.addingTimeInterval(5))

        stream.emit(angle: 105, at: base.addingTimeInterval(6))
        XCTAssertEqual(recorder.events, [])

        stream.emit(angle: policy.sleepThreshold, at: base.addingTimeInterval(7))
        scheduler.fire(at: base.addingTimeInterval(9))
        stream.emit(angle: policy.sleepThreshold - 1, at: base.addingTimeInterval(10))
        XCTAssertEqual(recorder.events, [.sleepRequestAttempted, .wouldSleep])

        stream.emit(angle: policy.reopenThreshold, at: base.addingTimeInterval(11))
        XCTAssertEqual(
            recorder.transitions,
            [.startupCooldown, .disarmed, .rearmed, .candidateStarted, .triggered, .rearmed]
        )
        stream.emit(angle: policy.sleepThreshold, at: base.addingTimeInterval(12))
        scheduler.fire(at: base.addingTimeInterval(14))
        XCTAssertEqual(
            recorder.events,
            [.sleepRequestAttempted, .wouldSleep, .sleepRequestAttempted, .wouldSleep]
        )

        coordinator.stop()
    }

    func testExecuteSleepCompositionUsesInjectedSystemOperationOnlyWhenExplicit() throws {
        let base = Date(timeIntervalSince1970: 4_000)
        let policy = LidSleepPolicy.calibratedDefault
        let stream = IntegrationReportStream()
        let scheduler = IntegrationScheduler()
        let operation = IntegrationSystemSleepOperation()

        let coordinator = AutoSleepComposition.makeCoordinator(
            stream: stream,
            decoder: CompositeLidAngleDecoder(decoders: [ReportID1DegreesDecoder()]),
            scheduler: scheduler,
            wakeObserver: IntegrationWakeObserver(),
            executionMode: .executeSleep,
            policy: policy,
            now: { base },
            systemSleepOperation: operation,
            onOperationalEvent: { _ in }
        )

        try coordinator.start()
        scheduler.fire(at: base.addingTimeInterval(5))
        stream.emit(angle: policy.reopenThreshold, at: base.addingTimeInterval(6))
        stream.emit(angle: policy.sleepThreshold, at: base.addingTimeInterval(7))
        scheduler.fire(at: base.addingTimeInterval(9))

        XCTAssertEqual(operation.requestCount, 1)
        coordinator.stop()
    }

    func testCancellingCandidateEmitsCandidateCancelledInsteadOfRearmed() throws {
        let base = Date(timeIntervalSince1970: 5_000)
        let policy = LidSleepPolicy.calibratedDefault
        let stream = IntegrationReportStream()
        let scheduler = IntegrationScheduler()
        let recorder = IntegrationEventRecorder()

        let coordinator = AutoSleepComposition.makeCoordinator(
            stream: stream,
            decoder: CompositeLidAngleDecoder(decoders: [ReportID1DegreesDecoder()]),
            scheduler: scheduler,
            wakeObserver: IntegrationWakeObserver(),
            executionMode: .dryRun,
            policy: policy,
            now: { base },
            onOperationalEvent: recorder.record,
            onTransitionEvent: recorder.recordTransition
        )

        try coordinator.start()
        scheduler.fire(at: base.addingTimeInterval(5))
        stream.emit(angle: 90, at: base.addingTimeInterval(6))
        stream.emit(angle: policy.sleepThreshold, at: base.addingTimeInterval(7))
        stream.emit(angle: 90, at: base.addingTimeInterval(8))

        XCTAssertEqual(
            recorder.transitions,
            [.startupCooldown, .disarmed, .rearmed, .candidateStarted, .candidateCancelled]
        )
        XCTAssertEqual(recorder.events, [])

        coordinator.stop()
    }

    func testDryRunWakeWhileClosedRequestsSecondWouldSleepAfterRecovery() throws {
        let base = Date(timeIntervalSince1970: 6_000)
        let policy = LidSleepPolicy.calibratedDefault
        let stream = IntegrationReportStream()
        let scheduler = IntegrationScheduler()
        let wakeObserver = IntegrationWakeObserver()
        let recorder = IntegrationEventRecorder()

        let coordinator = AutoSleepComposition.makeCoordinator(
            stream: stream,
            decoder: CompositeLidAngleDecoder(decoders: [ReportID1DegreesDecoder()]),
            scheduler: scheduler,
            wakeObserver: wakeObserver,
            executionMode: .dryRun,
            policy: policy,
            now: { base },
            onOperationalEvent: recorder.record,
            onTransitionEvent: recorder.recordTransition
        )

        try coordinator.start()
        scheduler.fire(at: base.addingTimeInterval(5))
        stream.emit(angle: policy.reopenThreshold, at: base.addingTimeInterval(6))
        stream.emit(angle: policy.sleepThreshold, at: base.addingTimeInterval(7))
        scheduler.fire(at: base.addingTimeInterval(9))

        wakeObserver.emitWake(at: base.addingTimeInterval(20))
        stream.emit(angle: policy.sleepThreshold, at: base.addingTimeInterval(21))
        scheduler.fire(at: base.addingTimeInterval(35))

        XCTAssertEqual(
            recorder.events,
            [.sleepRequestAttempted, .wouldSleep, .sleepRequestAttempted, .wouldSleep]
        )
        XCTAssertEqual(
            recorder.transitions.suffix(2),
            [.wakeRecovery, .recoveryResleep]
        )
        coordinator.stop()
    }

    func testDryRunReopenDuringRecoveryCancelsSecondWouldSleep() throws {
        let base = Date(timeIntervalSince1970: 7_000)
        let policy = LidSleepPolicy.calibratedDefault
        let stream = IntegrationReportStream()
        let scheduler = IntegrationScheduler()
        let wakeObserver = IntegrationWakeObserver()
        let recorder = IntegrationEventRecorder()

        let coordinator = AutoSleepComposition.makeCoordinator(
            stream: stream,
            decoder: CompositeLidAngleDecoder(decoders: [ReportID1DegreesDecoder()]),
            scheduler: scheduler,
            wakeObserver: wakeObserver,
            executionMode: .dryRun,
            policy: policy,
            now: { base },
            onOperationalEvent: recorder.record,
            onTransitionEvent: recorder.recordTransition
        )

        try coordinator.start()
        scheduler.fire(at: base.addingTimeInterval(5))
        stream.emit(angle: policy.reopenThreshold, at: base.addingTimeInterval(6))
        stream.emit(angle: policy.sleepThreshold, at: base.addingTimeInterval(7))
        scheduler.fire(at: base.addingTimeInterval(9))

        wakeObserver.emitWake(at: base.addingTimeInterval(20))
        stream.emit(angle: policy.reopenThreshold, at: base.addingTimeInterval(21))
        scheduler.fire(at: base.addingTimeInterval(35))

        XCTAssertEqual(recorder.events, [.sleepRequestAttempted, .wouldSleep])
        XCTAssertEqual(recorder.transitions.suffix(2), [.wakeRecovery, .rearmed])
        coordinator.stop()
    }

    func testExecuteSleepFailureIsReportedAndDisarmedEndToEnd() throws {
        let base = Date(timeIntervalSince1970: 8_000)
        let policy = LidSleepPolicy.calibratedDefault
        let stream = IntegrationReportStream()
        let scheduler = IntegrationScheduler()
        let operation = IntegrationSystemSleepOperation(
            error: IntegrationSleepError.failed
        )
        let recorder = IntegrationEventRecorder()

        let coordinator = AutoSleepComposition.makeCoordinator(
            stream: stream,
            decoder: CompositeLidAngleDecoder(decoders: [ReportID1DegreesDecoder()]),
            scheduler: scheduler,
            wakeObserver: IntegrationWakeObserver(),
            executionMode: .executeSleep,
            policy: policy,
            now: { base },
            systemSleepOperation: operation,
            onOperationalEvent: recorder.record,
            onTransitionEvent: recorder.recordTransition
        )

        try coordinator.start()
        scheduler.fire(at: base.addingTimeInterval(5))
        stream.emit(angle: policy.reopenThreshold, at: base.addingTimeInterval(6))
        stream.emit(angle: policy.sleepThreshold, at: base.addingTimeInterval(7))
        scheduler.fire(at: base.addingTimeInterval(9))
        stream.emit(angle: policy.sleepThreshold - 1, at: base.addingTimeInterval(10))

        XCTAssertEqual(operation.requestCount, 1)
        XCTAssertEqual(
            recorder.events,
            [.sleepRequestAttempted, .sleepRequestFailed("integration-sleep-failure")]
        )
        XCTAssertEqual(recorder.transitions.suffix(2), [.triggered, .disarmed])
        coordinator.stop()
    }
}

private final class IntegrationReportStream: HIDReportStreaming, @unchecked Sendable {
    private var callback: (@Sendable (HIDReport) -> Void)?

    func start(onReport: @escaping @Sendable (HIDReport) -> Void) throws {
        callback = onReport
    }

    func stop() {
        callback = nil
    }

    func emit(angle: Int, at date: Date) {
        callback?(
            HIDReport(
                reportID: 1,
                bytes: [1, UInt8(angle & 0xFF), UInt8((angle >> 8) & 0xFF)],
                timestamp: date
            )
        )
    }
}

private final class IntegrationScheduler: OneShotScheduling, @unchecked Sendable {
    private var tasks: [Date: IntegrationTask] = [:]

    func schedule(
        at deadline: Date,
        _ action: @escaping @Sendable () -> Void
    ) -> CancellableTask {
        let task = IntegrationTask(action: action)
        tasks[deadline] = task
        return task
    }

    func fire(at deadline: Date) {
        tasks.removeValue(forKey: deadline)?.fire()
    }
}

private final class IntegrationTask: CancellableTask, @unchecked Sendable {
    private let action: @Sendable () -> Void
    private var cancelled = false

    init(action: @escaping @Sendable () -> Void) {
        self.action = action
    }

    func cancel() {
        cancelled = true
    }

    func fire() {
        guard !cancelled else { return }
        action()
    }
}

private final class IntegrationWakeObserver: SystemWakeObserving, @unchecked Sendable {
    private var callback: (@Sendable (Date) -> Void)?

    func start(onWake: @escaping @Sendable (Date) -> Void) throws {
        callback = onWake
    }

    func stop() {
        callback = nil
    }

    func emitWake(at date: Date) {
        callback?(date)
    }
}

private final class IntegrationSystemSleepOperation: SystemSleepOperating, @unchecked Sendable {
    private let error: Error?
    private(set) var requestCount = 0

    init(error: Error? = nil) {
        self.error = error
    }

    func requestSleep() throws {
        requestCount += 1
        if let error {
            throw error
        }
    }
}

private enum IntegrationSleepError: Error, CustomStringConvertible {
    case failed

    var description: String { "integration-sleep-failure" }
}

private final class IntegrationEventRecorder: @unchecked Sendable {
    private(set) var events: [AutoSleepOperationalEvent] = []
    private(set) var transitions: [AutoSleepTransitionEvent] = []

    func record(_ event: AutoSleepOperationalEvent) {
        events.append(event)
    }

    func recordTransition(_ event: AutoSleepTransitionEvent) {
        transitions.append(event)
    }
}
