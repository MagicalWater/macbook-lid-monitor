import XCTest
@testable import LidMonitorCore

final class LidSleepStateMachineTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)
    private let policy = try! LidSleepPolicy(
        sleepThreshold: 60,
        reopenThreshold: 70,
        closeDebounce: 2,
        startupCooldown: 5,
        wakeRecovery: 15
    )

    func testStartupAtOpenAngleArmsOpenState() {
        var machine = makeMachine()
        _ = machine.handle(.angleChanged(70, at: start.addingTimeInterval(1)))

        XCTAssertEqual(
            machine.handle(.startupCooldownElapsed(at: start.addingTimeInterval(5))),
            [.stateChanged(.open)]
        )
        XCTAssertEqual(machine.state, .open)
    }

    func testStartupBelowReopenThresholdStaysDisarmed() {
        var machine = makeMachine()
        _ = machine.handle(.angleChanged(69, at: start.addingTimeInterval(1)))

        XCTAssertEqual(
            machine.handle(.startupCooldownElapsed(at: start.addingTimeInterval(5))),
            [.stateChanged(.disarmed)]
        )
        XCTAssertEqual(machine.state, .disarmed)
    }

    func testNormalCloseDebounceRequestsSleepOnce() {
        var machine = armedMachine()
        let close = start.addingTimeInterval(6)
        let deadline = close.addingTimeInterval(2)

        XCTAssertEqual(
            machine.handle(.angleChanged(60, at: close)),
            [
                .stateChanged(.closingCandidate(deadline: deadline)),
                .scheduleCloseDebounce(deadline: deadline)
            ]
        )
        XCTAssertEqual(
            machine.handle(.closeDebounceElapsed(at: deadline)),
            [.stateChanged(.triggered), .requestSleep]
        )
        XCTAssertEqual(
            machine.handle(.closeDebounceElapsed(at: deadline.addingTimeInterval(1))),
            []
        )
    }

    func testOpeningAboveSleepThresholdCancelsCloseCandidate() {
        var machine = armedMachine()
        _ = machine.handle(.angleChanged(60, at: start.addingTimeInterval(6)))

        XCTAssertEqual(
            machine.handle(.angleChanged(61, at: start.addingTimeInterval(7))),
            [.cancelCloseDebounce, .stateChanged(.open)]
        )
    }

    func testWakeClearsPreSleepAngleAndSchedulesRecovery() {
        var machine = triggeredMachine()
        let wake = start.addingTimeInterval(20)
        let deadline = wake.addingTimeInterval(15)

        XCTAssertEqual(
            machine.handle(.systemDidWake(at: wake)),
            [
                .stateChanged(.wakeRecovery(deadline: deadline)),
                .scheduleWakeRecovery(deadline: deadline)
            ]
        )
        XCTAssertEqual(
            machine.handle(.wakeRecoveryElapsed(at: deadline)),
            [.stateChanged(.disarmed)]
        )
    }

    func testFreshReopenDuringRecoveryCancelsResleep() {
        var machine = recoveryMachine()

        XCTAssertEqual(
            machine.handle(.angleChanged(70, at: start.addingTimeInterval(21))),
            [.cancelWakeRecovery, .stateChanged(.open)]
        )
        XCTAssertEqual(machine.state, .open)
    }

    func testFreshClosedAngleAtRecoveryDeadlineRequestsSleep() {
        var machine = recoveryMachine()
        let deadline = start.addingTimeInterval(35)
        _ = machine.handle(.angleChanged(60, at: start.addingTimeInterval(21)))

        XCTAssertEqual(
            machine.handle(.wakeRecoveryElapsed(at: deadline)),
            [.stateChanged(.triggered), .requestSleep]
        )
    }

    func testHysteresisAngleAtRecoveryDeadlineRequestsSleep() {
        var machine = recoveryMachine()
        let deadline = start.addingTimeInterval(35)
        _ = machine.handle(.angleChanged(69, at: start.addingTimeInterval(21)))

        XCTAssertEqual(
            machine.handle(.wakeRecoveryElapsed(at: deadline)),
            [.stateChanged(.triggered), .requestSleep]
        )
    }

    func testInvalidRecoveryDataClearsEarlierClosedEvidence() {
        var machine = recoveryMachine()
        let deadline = start.addingTimeInterval(35)
        _ = machine.handle(.angleChanged(60, at: start.addingTimeInterval(21)))
        XCTAssertEqual(
            machine.handle(.dataInvalid(at: start.addingTimeInterval(22))),
            []
        )

        XCTAssertEqual(
            machine.handle(.wakeRecoveryElapsed(at: deadline)),
            [.stateChanged(.disarmed)]
        )
    }

    func testEveryWakeReplacesRecoveryWithFreshDeadline() {
        var machine = recoveryMachine()
        let secondWake = start.addingTimeInterval(25)
        let secondDeadline = secondWake.addingTimeInterval(15)

        XCTAssertEqual(
            machine.handle(.systemDidWake(at: secondWake)),
            [
                .cancelWakeRecovery,
                .stateChanged(.wakeRecovery(deadline: secondDeadline)),
                .scheduleWakeRecovery(deadline: secondDeadline)
            ]
        )
    }

    func testSleepRequestFailureDisarmsUntilReopened() {
        var machine = triggeredMachine()

        XCTAssertEqual(
            machine.handle(.sleepRequestFailed(at: start.addingTimeInterval(9))),
            [.stateChanged(.disarmed)]
        )
        XCTAssertEqual(
            machine.handle(.angleChanged(69, at: start.addingTimeInterval(10))),
            []
        )
        XCTAssertEqual(
            machine.handle(.angleChanged(70, at: start.addingTimeInterval(11))),
            [.stateChanged(.open)]
        )
    }

    func testInvalidDataCancelsNormalCloseCandidate() {
        var machine = armedMachine()
        _ = machine.handle(.angleChanged(60, at: start.addingTimeInterval(6)))

        XCTAssertEqual(
            machine.handle(.dataInvalid(at: start.addingTimeInterval(7))),
            [.cancelCloseDebounce, .stateChanged(.open)]
        )
    }

    private func makeMachine() -> LidSleepStateMachine {
        LidSleepStateMachine(policy: policy)
    }

    private func armedMachine() -> LidSleepStateMachine {
        var machine = makeMachine()
        _ = machine.handle(.angleChanged(70, at: start))
        _ = machine.handle(.startupCooldownElapsed(at: start.addingTimeInterval(5)))
        return machine
    }

    private func triggeredMachine() -> LidSleepStateMachine {
        var machine = armedMachine()
        _ = machine.handle(.angleChanged(60, at: start.addingTimeInterval(6)))
        _ = machine.handle(.closeDebounceElapsed(at: start.addingTimeInterval(8)))
        return machine
    }

    private func recoveryMachine() -> LidSleepStateMachine {
        var machine = triggeredMachine()
        _ = machine.handle(.systemDidWake(at: start.addingTimeInterval(20)))
        return machine
    }
}
