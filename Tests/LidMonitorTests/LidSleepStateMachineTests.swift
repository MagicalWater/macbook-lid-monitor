import XCTest
@testable import LidMonitor

final class LidSleepStateMachineTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)
    private let policy = try! LidSleepPolicy(
        sleepThreshold: 60,
        reopenThreshold: 70,
        debounce: 2,
        wakeCooldown: 5
    )

    func testCooldownEndingAtOpenAngleArmsOpenState() {
        var machine = makeMachine()

        XCTAssertEqual(
            machine.handle(.angleChanged(70, at: start.addingTimeInterval(1))),
            []
        )
        XCTAssertEqual(
            machine.handle(.cooldownElapsed(at: start.addingTimeInterval(5))),
            [.stateChanged(.open)]
        )
        XCTAssertEqual(machine.state, .open)
    }

    func testCooldownEndingBelowReopenThresholdStaysDisarmed() {
        var machine = makeMachine()

        _ = machine.handle(.angleChanged(60, at: start.addingTimeInterval(1)))

        XCTAssertEqual(
            machine.handle(.cooldownElapsed(at: start.addingTimeInterval(5))),
            [.stateChanged(.disarmed)]
        )
        XCTAssertEqual(machine.state, .disarmed)
        XCTAssertEqual(
            machine.handle(.angleChanged(69, at: start.addingTimeInterval(6))),
            []
        )
        XCTAssertEqual(
            machine.handle(.angleChanged(70, at: start.addingTimeInterval(7))),
            [.stateChanged(.open)]
        )
    }

    func testAngle61StaysOpen() {
        var machine = armedMachine()

        XCTAssertEqual(
            machine.handle(.angleChanged(61, at: start.addingTimeInterval(6))),
            []
        )
        XCTAssertEqual(machine.state, .open)
    }

    func testAngle60SchedulesOneDebounceDeadline() {
        var machine = armedMachine()
        let eventTime = start.addingTimeInterval(6)
        let deadline = eventTime.addingTimeInterval(2)

        XCTAssertEqual(
            machine.handle(.angleChanged(60, at: eventTime)),
            [
                .stateChanged(.closingCandidate(deadline: deadline)),
                .scheduleDebounce(deadline: deadline)
            ]
        )
        XCTAssertEqual(machine.state, .closingCandidate(deadline: deadline))
    }

    func testDuplicateClosedReportsDoNotExtendDebounce() {
        var machine = armedMachine()
        let first = start.addingTimeInterval(6)
        let deadline = first.addingTimeInterval(2)
        _ = machine.handle(.angleChanged(60, at: first))

        XCTAssertEqual(
            machine.handle(.angleChanged(59, at: first.addingTimeInterval(1))),
            []
        )
        XCTAssertEqual(machine.state, .closingCandidate(deadline: deadline))
    }

    func testAngle61BeforeDeadlineCancelsCandidate() {
        var machine = armedMachine()
        _ = machine.handle(.angleChanged(60, at: start.addingTimeInterval(6)))

        XCTAssertEqual(
            machine.handle(.angleChanged(61, at: start.addingTimeInterval(7))),
            [.cancelDebounce, .stateChanged(.open)]
        )
        XCTAssertEqual(machine.state, .open)
    }

    func testDebounceElapsedRequestsSleepOnlyOnce() {
        var machine = armedMachine()
        let deadline = start.addingTimeInterval(8)
        _ = machine.handle(.angleChanged(60, at: start.addingTimeInterval(6)))

        XCTAssertEqual(
            machine.handle(.debounceElapsed(at: deadline)),
            [.stateChanged(.triggered), .requestSleep]
        )
        XCTAssertEqual(
            machine.handle(.debounceElapsed(at: deadline.addingTimeInterval(1))),
            []
        )
    }

    func testTriggeredStateRearmsOnlyAt70() {
        var machine = triggeredMachine()

        for angle in [61, 69] {
            XCTAssertEqual(
                machine.handle(.angleChanged(angle, at: start.addingTimeInterval(9))),
                []
            )
            XCTAssertEqual(machine.state, .triggered)
        }

        XCTAssertEqual(
            machine.handle(.angleChanged(70, at: start.addingTimeInterval(10))),
            [.stateChanged(.open)]
        )
    }

    func testInvalidDataCancelsCandidateAndFailsOpen() {
        var machine = armedMachine()
        _ = machine.handle(.angleChanged(60, at: start.addingTimeInterval(6)))

        XCTAssertEqual(
            machine.handle(.dataInvalid(at: start.addingTimeInterval(7))),
            [.cancelDebounce, .stateChanged(.open)]
        )
        XCTAssertEqual(machine.state, .open)
    }

    func testSystemWakeCancelsCandidateAndReturnsToCooldown() {
        var machine = armedMachine()
        _ = machine.handle(.angleChanged(60, at: start.addingTimeInterval(6)))

        XCTAssertEqual(
            machine.handle(.systemDidWake(at: start.addingTimeInterval(7))),
            [.cancelDebounce, .stateChanged(.cooldown)]
        )
        XCTAssertEqual(machine.state, .cooldown)
    }

    private func makeMachine() -> LidSleepStateMachine {
        LidSleepStateMachine(policy: policy)
    }

    private func armedMachine() -> LidSleepStateMachine {
        var machine = makeMachine()
        _ = machine.handle(.angleChanged(70, at: start))
        _ = machine.handle(.cooldownElapsed(at: start.addingTimeInterval(5)))
        return machine
    }

    private func triggeredMachine() -> LidSleepStateMachine {
        var machine = armedMachine()
        _ = machine.handle(.angleChanged(60, at: start.addingTimeInterval(6)))
        _ = machine.handle(.debounceElapsed(at: start.addingTimeInterval(8)))
        return machine
    }
}
