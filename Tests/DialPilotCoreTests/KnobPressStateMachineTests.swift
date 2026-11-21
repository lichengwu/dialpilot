import XCTest
@testable import DialPilotCore

final class KnobPressStateMachineTests: XCTestCase {
    func testSinglePressWaitsUntilDoubleClickWindowCloses() {
        var machine = KnobPressStateMachine(doublePressInterval: 0.28)

        XCTAssertEqual(machine.pressDown(at: 10), [])
        XCTAssertEqual(machine.pressUp(at: 10.1), [.scheduleSinglePress(after: 0.28)])
        XCTAssertEqual(machine.singlePressTimerFired(), .performSinglePress)
        XCTAssertNil(machine.singlePressTimerFired())
    }

    func testDoublePressCancelsSingleAndPerformsDoubleOnly() {
        var machine = KnobPressStateMachine()

        _ = machine.pressDown(at: 20)
        _ = machine.pressUp(at: 20.08)
        XCTAssertEqual(machine.pressDown(at: 20.20), [.cancelPendingSinglePress])
        XCTAssertNil(machine.singlePressTimerFired())
        XCTAssertEqual(machine.pressUp(at: 20.27), [
            .cancelPendingSinglePress,
            .performDoublePress
        ])
    }

    func testLongHoldIsJustASinglePressOnRelease() {
        // No long-press gesture. A hold longer than the double-click
        // window releases as an ordinary single press (scheduled), never
        // a profile switch.
        var machine = KnobPressStateMachine()
        _ = machine.pressDown(at: 30)
        XCTAssertEqual(machine.pressUp(at: 31), [.scheduleSinglePress(after: 0.28)])
        XCTAssertEqual(machine.singlePressTimerFired(), .performSinglePress)
    }

    func testPressAfterExpiredWindowFlushesFirstSingle() {
        var machine = KnobPressStateMachine(doublePressInterval: 0.28)
        _ = machine.pressDown(at: 50)
        _ = machine.pressUp(at: 50.1)

        XCTAssertEqual(machine.pressDown(at: 50.5), [
            .cancelPendingSinglePress,
            .performSinglePress
        ])
    }

    func testRepeatDownStrayUpAndResetAreSafe() {
        var machine = KnobPressStateMachine()
        XCTAssertEqual(machine.pressUp(at: 1), [])
        XCTAssertEqual(machine.pressDown(at: 2), [])
        XCTAssertEqual(machine.pressDown(at: 2.1), [])
        machine.reset()
        XCTAssertNil(machine.singlePressTimerFired())
        XCTAssertEqual(machine.pressUp(at: 3), [])
    }
}