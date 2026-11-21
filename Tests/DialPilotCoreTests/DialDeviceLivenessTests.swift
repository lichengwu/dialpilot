import XCTest
@testable import DialPilotCore

/// The AU05 answers power queries while awake and goes completely silent when
/// switched off, even though USB keeps it enumerated. These tests pin the
/// counting rule that turns that silence into "not responding".
final class DialDeviceLivenessTests: XCTestCase {
    func testFreshDeviceIsOptimistic() {
        let liveness = DialDeviceLiveness()
        XCTAssertTrue(liveness.isResponsive)
        XCTAssertEqual(liveness.silentPolls, 0)
    }

    func testOneSilentPollDoesNotFlipTheUi() {
        var liveness = DialDeviceLiveness()
        liveness.pollSent()
        XCTAssertTrue(liveness.isResponsive, "a single dropped report is a hiccup, not a power-off")
        XCTAssertEqual(liveness.silentPolls, 1)
    }

    func testTwoSilentPollsMarkUnresponsive() {
        var liveness = DialDeviceLiveness()
        liveness.pollSent()
        liveness.pollSent()
        XCTAssertFalse(liveness.isResponsive)
    }

    func testReplyClearsSilence() {
        var liveness = DialDeviceLiveness()
        liveness.pollSent()
        liveness.replyReceived()
        XCTAssertEqual(liveness.silentPolls, 0)
        XCTAssertTrue(liveness.isResponsive)
    }

    func testReplyAfterGoingSilentRestoresResponsiveness() {
        var liveness = DialDeviceLiveness()
        liveness.pollSent()
        liveness.pollSent()
        XCTAssertFalse(liveness.isResponsive)
        liveness.replyReceived()
        XCTAssertTrue(liveness.isResponsive)
        XCTAssertEqual(liveness.silentPolls, 0)
    }

    func testResetForgetsThePastOnReattach() {
        var liveness = DialDeviceLiveness()
        liveness.pollSent()
        liveness.pollSent()
        liveness.reset()
        XCTAssertTrue(liveness.isResponsive)
        XCTAssertEqual(liveness.silentPolls, 0)
    }

    /// While silent, poll far more often so the badge recovers within seconds
    /// of the knob being switched back on — but never slower than the caller.
    func testSilentDevicePollsFasterWithoutSpeedingUpTheHappyPath() {
        var liveness = DialDeviceLiveness()
        XCTAssertEqual(liveness.pollInterval(whileAlive: 75), 75)
        XCTAssertEqual(liveness.pollInterval(whileAlive: 3), 3)

        liveness.pollSent()
        liveness.pollSent()
        XCTAssertEqual(liveness.pollInterval(whileAlive: 75), 8)
        XCTAssertEqual(liveness.pollInterval(whileAlive: 3), 3)
        XCTAssertEqual(liveness.pollInterval(whileAlive: 0), 0, "polling disabled stays disabled")
    }
}
