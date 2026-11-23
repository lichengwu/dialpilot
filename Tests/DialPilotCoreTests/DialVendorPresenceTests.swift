import XCTest
@testable import DialPilotCore

/// The Studio handover must not depend on workspace notifications: on
/// 2026-11-23 a real Studio exit delivered no didTerminate callback and the
/// listener stayed down. These pin the observation-based diff that every
/// refreshUI now runs.
final class DialVendorPresenceTests: XCTestCase {
    func testFirstObservationIsNotATransition() {
        var presence = DialVendorPresence()
        XCTAssertEqual(presence.observe(running: true), .unchanged)
        var other = DialVendorPresence()
        XCTAssertEqual(other.observe(running: false), .unchanged)
    }

    func testExitAfterRunningIsDetected() {
        var presence = DialVendorPresence()
        _ = presence.observe(running: true)
        XCTAssertEqual(presence.observe(running: false), .exited)
    }

    func testLaunchAfterAbsentIsDetected() {
        var presence = DialVendorPresence()
        _ = presence.observe(running: false)
        XCTAssertEqual(presence.observe(running: true), .appeared)
    }

    func testStablePresenceNeverRetriggers() {
        var presence = DialVendorPresence()
        _ = presence.observe(running: true)
        for _ in 0..<5 {
            XCTAssertEqual(presence.observe(running: true), .unchanged)
        }
        XCTAssertEqual(presence.observe(running: false), .exited)
        for _ in 0..<5 {
            XCTAssertEqual(presence.observe(running: false), .unchanged)
        }
    }

    func testFullHandoverCycle() {
        var presence = DialVendorPresence()
        XCTAssertEqual(presence.observe(running: false), .unchanged) // launch, no Studio
        XCTAssertEqual(presence.observe(running: true), .appeared)   // Studio opens
        XCTAssertEqual(presence.observe(running: true), .unchanged)  // still there
        XCTAssertEqual(presence.observe(running: false), .exited)    // user quits it
        XCTAssertEqual(presence.observe(running: true), .appeared)   // opens again
        XCTAssertEqual(presence.observe(running: false), .exited)    // quits again
    }
}
