import Foundation
import XCTest
@testable import LidMonitor

final class AutoSleepIntegrationTests: XCTestCase {
    func testDryRunCompositionProcessesCalibratedCloseCycleEndToEnd() throws {
        let base = Date(timeIntervalSince1970: 3_000)
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
            policy: .calibratedDefault,
            now: { base },
            onOperationalEvent: recorder.record,
            onTransitionEvent: recorder.recordTransition
        )

        try coordinator.start()
        scheduler.fire(at: base.addingTimeInterval(5))

        stream.emit(angle: 105, at: base.addingTimeInterval(6))
        XCTAssertEqual(recorder.events, [])

        stream.emit(angle: 60, at: base.addingTimeInterval(7))
        scheduler.fire(at: base.addingTimeInterval(9))
        stream.emit(angle: 59, at: base.addingTimeInterval(10))
        XCTAssertEqual(recorder.events, [.wouldSleep])

        stream.emit(angle: 70, at: base.addingTimeInterval(11))
        XCTAssertEqual(
            recorder.transitions,
            [.disarmed, .rearmed, .candidateStarted, .triggered, .rearmed]
        )
        stream.emit(angle: 60, at: base.addingTimeInterval(12))
        scheduler.fire(at: base.addingTimeInterval(14))
        XCTAssertEqual(recorder.events, [.wouldSleep, .wouldSleep])

        coordinator.stop()
    }

    func testExecuteSleepCompositionUsesInjectedSystemOperationOnlyWhenExplicit() throws {
        let base = Date(timeIntervalSince1970: 4_000)
        let stream = IntegrationReportStream()
        let scheduler = IntegrationScheduler()
        let operation = IntegrationSystemSleepOperation()

        let coordinator = AutoSleepComposition.makeCoordinator(
            stream: stream,
            decoder: CompositeLidAngleDecoder(decoders: [ReportID1DegreesDecoder()]),
            scheduler: scheduler,
            wakeObserver: IntegrationWakeObserver(),
            executionMode: .executeSleep,
            policy: .calibratedDefault,
            now: { base },
            systemSleepOperation: operation,
            onOperationalEvent: { _ in }
        )

        try coordinator.start()
        scheduler.fire(at: base.addingTimeInterval(5))
        stream.emit(angle: 70, at: base.addingTimeInterval(6))
        stream.emit(angle: 60, at: base.addingTimeInterval(7))
        scheduler.fire(at: base.addingTimeInterval(9))

        XCTAssertEqual(operation.requestCount, 1)
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
    func start(onWake: @escaping @Sendable (Date) -> Void) {}
    func stop() {}
}

private final class IntegrationSystemSleepOperation: SystemSleepOperating, @unchecked Sendable {
    private(set) var requestCount = 0

    func requestSleep() throws {
        requestCount += 1
    }
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
