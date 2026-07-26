import Foundation
import XCTest
@testable import LidMonitor

final class LidSleepCoordinatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000)
    private let policy = try! LidSleepPolicy(
        sleepThreshold: 60,
        reopenThreshold: 70,
        debounce: 2,
        wakeCooldown: 5
    )

    func testStartSubscribesOnceAndSchedulesStartupCooldown() throws {
        let fixture = makeFixture()

        try fixture.coordinator.start()
        try fixture.coordinator.start()

        XCTAssertEqual(fixture.stream.startCount, 1)
        XCTAssertEqual(fixture.wakeObserver.startCount, 1)
        XCTAssertEqual(fixture.scheduler.pendingDeadlines, [now.addingTimeInterval(5)])
    }

    func testAngle60SchedulesOneDebounceAnd61CancelsIt() throws {
        let fixture = makeFixture()
        try fixture.coordinator.start()
        fixture.stream.send(angle: 70, at: now)
        fixture.scheduler.fire(deadline: now.addingTimeInterval(5))

        fixture.stream.send(angle: 60, at: now.addingTimeInterval(6))
        XCTAssertEqual(
            fixture.scheduler.pendingDeadlines,
            [now.addingTimeInterval(8)]
        )

        fixture.stream.send(angle: 59, at: now.addingTimeInterval(7))
        XCTAssertEqual(
            fixture.scheduler.pendingDeadlines,
            [now.addingTimeInterval(8)]
        )

        fixture.stream.send(angle: 61, at: now.addingTimeInterval(7.5))
        XCTAssertTrue(fixture.scheduler.pendingDeadlines.isEmpty)
        XCTAssertEqual(fixture.requester.requestCount, 0)
    }

    func testFiringDebounceRequestsSleepOnce() throws {
        let fixture = makeFixture()
        try fixture.coordinator.start()
        arm(fixture)

        fixture.stream.send(angle: 60, at: now.addingTimeInterval(6))
        fixture.scheduler.fire(deadline: now.addingTimeInterval(8))
        fixture.scheduler.fire(deadline: now.addingTimeInterval(8))

        XCTAssertEqual(fixture.requester.requestCount, 1)
    }

    func testWakeCancelsDebounceAndStartsFreshCooldown() throws {
        let fixture = makeFixture()
        try fixture.coordinator.start()
        arm(fixture)
        fixture.stream.send(angle: 60, at: now.addingTimeInterval(6))

        fixture.wakeObserver.sendWake(at: now.addingTimeInterval(7))

        XCTAssertEqual(
            fixture.scheduler.pendingDeadlines,
            [now.addingTimeInterval(12)]
        )
        fixture.stream.send(angle: 60, at: now.addingTimeInterval(8))
        fixture.scheduler.fire(deadline: now.addingTimeInterval(12))
        fixture.stream.send(angle: 69, at: now.addingTimeInterval(13))
        XCTAssertEqual(fixture.requester.requestCount, 0)

        fixture.stream.send(angle: 70, at: now.addingTimeInterval(14))
        fixture.stream.send(angle: 60, at: now.addingTimeInterval(15))
        fixture.scheduler.fire(deadline: now.addingTimeInterval(17))
        XCTAssertEqual(fixture.requester.requestCount, 1)
    }

    func testDecodeFailureNeverRequestsSleep() throws {
        let fixture = makeFixture()
        try fixture.coordinator.start()
        arm(fixture)

        fixture.stream.send(angle: 60, at: now.addingTimeInterval(6))
        fixture.stream.sendInvalid(at: now.addingTimeInterval(7))
        fixture.scheduler.fire(deadline: now.addingTimeInterval(8))

        XCTAssertEqual(fixture.requester.requestCount, 0)
        XCTAssertTrue(fixture.scheduler.pendingDeadlines.isEmpty)
    }

    func testStopIsIdempotentAndCancelsAllWork() throws {
        let fixture = makeFixture()
        try fixture.coordinator.start()
        arm(fixture)
        fixture.stream.send(angle: 60, at: now.addingTimeInterval(6))

        fixture.coordinator.stop()
        fixture.coordinator.stop()

        XCTAssertEqual(fixture.stream.stopCount, 1)
        XCTAssertEqual(fixture.wakeObserver.stopCount, 1)
        XCTAssertTrue(fixture.scheduler.pendingDeadlines.isEmpty)
    }

    private func arm(_ fixture: Fixture) {
        fixture.stream.send(angle: 70, at: now)
        fixture.scheduler.fire(deadline: now.addingTimeInterval(5))
    }

    private func makeFixture() -> Fixture {
        let currentDate = now
        let stream = FakeReportStream()
        let scheduler = ManualScheduler()
        let wakeObserver = FakeWakeObserver()
        let requester = SpySleepRequester()
        let coordinator = LidSleepCoordinator(
            stream: stream,
            decoder: CompositeLidAngleDecoder(
                decoders: [ReportID1DegreesDecoder()]
            ),
            scheduler: scheduler,
            wakeObserver: wakeObserver,
            sleepRequester: requester,
            policy: policy,
            now: { currentDate }
        )
        return Fixture(
            coordinator: coordinator,
            stream: stream,
            scheduler: scheduler,
            wakeObserver: wakeObserver,
            requester: requester
        )
    }
}

private struct Fixture {
    let coordinator: LidSleepCoordinator
    let stream: FakeReportStream
    let scheduler: ManualScheduler
    let wakeObserver: FakeWakeObserver
    let requester: SpySleepRequester
}

private final class FakeReportStream: HIDReportStreaming, @unchecked Sendable {
    private var callback: (@Sendable (HIDReport) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(onReport: @escaping @Sendable (HIDReport) -> Void) throws {
        startCount += 1
        callback = onReport
    }

    func stop() {
        stopCount += 1
        callback = nil
    }

    func send(angle: Int, at date: Date) {
        callback?(
            HIDReport(
                reportID: 1,
                bytes: [1, UInt8(angle & 0xFF), UInt8((angle >> 8) & 0xFF)],
                timestamp: date
            )
        )
    }

    func sendInvalid(at date: Date) {
        callback?(HIDReport(reportID: 1, bytes: [], timestamp: date))
    }
}

private final class ManualScheduler: OneShotScheduling, @unchecked Sendable {
    private var tasks: [Date: ManualTask] = [:]

    var pendingDeadlines: [Date] {
        tasks.compactMap { $0.value.isCancelled ? nil : $0.key }.sorted()
    }

    func schedule(
        at deadline: Date,
        _ action: @escaping @Sendable () -> Void
    ) -> CancellableTask {
        let task = ManualTask(action: action)
        tasks[deadline] = task
        return task
    }

    func fire(deadline: Date) {
        guard let task = tasks.removeValue(forKey: deadline),
              !task.isCancelled else { return }
        task.fire()
    }
}

private final class ManualTask: CancellableTask, @unchecked Sendable {
    private let action: @Sendable () -> Void
    private(set) var isCancelled = false

    init(action: @escaping @Sendable () -> Void) {
        self.action = action
    }

    func cancel() {
        isCancelled = true
    }

    func fire() {
        action()
    }
}

private final class FakeWakeObserver: SystemWakeObserving, @unchecked Sendable {
    private var callback: (@Sendable (Date) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(onWake: @escaping @Sendable (Date) -> Void) {
        startCount += 1
        callback = onWake
    }

    func stop() {
        stopCount += 1
        callback = nil
    }

    func sendWake(at date: Date) {
        callback?(date)
    }
}

private final class SpySleepRequester: SleepRequesting, @unchecked Sendable {
    private(set) var requestCount = 0

    func requestSleep() throws {
        requestCount += 1
    }
}
