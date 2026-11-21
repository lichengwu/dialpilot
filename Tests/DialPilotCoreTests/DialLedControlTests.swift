import XCTest
@testable import DialPilotCore

final class DialLedControlTests: XCTestCase {
    private func state(
        mode: UInt8 = 2,
        allOn: UInt8 = 7,
        leds: [DialLedTuple]? = nil
    ) -> DialLedState {
        DialLedState(
            mode: mode,
            allOnBrightness: allOn,
            leds: leds ?? [.baselineOff, .baselineOff, .baselineOff, .baselineOff]
        )
    }

    private func solid(_ brightness: UInt8, workTime: UInt8 = 255) -> DialLedTuple {
        DialLedTuple(
            workType: 1, workTime: workTime, breatheLevel: 2,
            breatheBrightness: 7, alwaysOnBrightness: brightness
        )
    }

    // MARK: - Frame layout

    func testReadPlaintextHeader() {
        let plaintext = DialLedControl.readPlaintext()
        XCTAssertEqual(plaintext.count, 64)
        XCTAssertEqual(Array(plaintext.prefix(4)), [0x01, 0x0B, 0x88, 0x01])
        XCTAssertTrue(plaintext.dropFirst(4).allSatisfy { $0 == 0 })
    }

    func testSetPlaintextCarriesFullFourLedRecord() {
        let target = state(leds: [.baselineOff, solid(15), .baselineOff, solid(7)])
        let plaintext = DialLedControl.setPlaintext(
            mask: DialLedControl.FieldMask.workType, focus: 1, state: target
        )
        XCTAssertEqual(plaintext.count, 64)
        XCTAssertEqual(Array(plaintext.prefix(8)), [
            0x01, 0x0B, 0x88, 0x04, 0x04, 0x01, 0x02, 0x07,
        ])
        // All four tuples ride along, not just the focused slot.
        XCTAssertEqual(Array(plaintext[8..<28]), target.leds.flatMap(\.bytes))
        XCTAssertTrue(plaintext.dropFirst(28).allSatisfy { $0 == 0 })
    }

    func testSetPlaintextModeAndAllOnOffsets() {
        let target = state(mode: 1, allOn: 15)
        let modeFrame = DialLedControl.setPlaintext(
            mask: DialLedControl.FieldMask.mode, focus: 0, state: target
        )
        XCTAssertEqual(modeFrame[6], 1)
        let brightFrame = DialLedControl.setPlaintext(
            mask: DialLedControl.FieldMask.allOnBrightness, focus: 0, state: target
        )
        XCTAssertEqual(brightFrame[7], 15)
    }

    func testSetReportEncryptsThroughCodec() throws {
        let target = state()
        let report = try DialLedControl.setReport(
            mask: DialLedControl.FieldMask.mode, focus: 0, state: target
        )
        XCTAssertEqual(report.count, 64)
        XCTAssertEqual(report[0], 0x55)
        let decrypted = try DialPacketCodec.decrypt(Array(report.dropFirst().prefix(56)))
        XCTAssertEqual(
            Array(decrypted.prefix(28)),
            Array(DialLedControl.setPlaintext(
                mask: DialLedControl.FieldMask.mode, focus: 0, state: target
            ).prefix(28))
        )
    }

    // MARK: - Validation domain

    func testValidateAcceptsBaseline() {
        XCTAssertNoThrow(try DialLedControl.validate(.baseline))
    }

    func testValidateRejectsBadMode() {
        XCTAssertThrowsError(try DialLedControl.validate(state(mode: 3))) { error in
            XCTAssertEqual(error as? DialLedControlError, .invalidMode(3))
        }
    }

    func testValidateRejectsWorkTypeAboveOneOnHostLeds() {
        var leds = state().leds
        leds[1].workType = 2
        XCTAssertThrowsError(try DialLedControl.validate(state(leds: leds))) { error in
            XCTAssertEqual(error as? DialLedControlError, .invalidWorkType(led: 1, value: 2))
        }
    }

    func testValidateAllowsFactoryBreatheOnLedZero() {
        // The stored baseline keeps workType 2 on the firmware-driven voice key.
        XCTAssertNoThrow(try DialLedControl.validate(.baseline))
    }

    func testValidateRejectsBrightnessAboveTwenty() {
        var leds = state().leds
        leds[3].alwaysOnBrightness = 21
        XCTAssertThrowsError(try DialLedControl.validate(state(leds: leds)))
    }

    func testValidateRejectsUnknownWorkTime() {
        var leds = state().leds
        leds[2].workTime = 30
        XCTAssertThrowsError(try DialLedControl.validate(state(leds: leds))) { error in
            XCTAssertEqual(error as? DialLedControlError, .invalidWorkTime(led: 2, value: 30))
        }
    }

    func testValidateRejectsWrongLedCount() {
        let short = DialLedState(mode: 2, allOnBrightness: 7, leds: [.baselineOff])
        XCTAssertThrowsError(try DialLedControl.validate(short)) { error in
            XCTAssertEqual(error as? DialLedControlError, .invalidLedCount(actual: 1))
        }
    }

    // MARK: - Diff ordering

    func testWritesEmptyWhenIdentical() throws {
        let writes = try DialLedControl.writes(desired: .baseline, expected: .baseline)
        XCTAssertTrue(writes.isEmpty)
    }

    func testWritesOrderWorkTimeBeforeBrightnessBeforeWorkType() throws {
        let expected = state()
        let desired = state(leds: [.baselineOff, solid(15), .baselineOff, .baselineOff])
        let writes = try DialLedControl.writes(desired: desired, expected: expected)
        let masks = writes.map(\.mask)
        // LED1: workTime(0x08) → alwaysOnBrightness(0x40) → workType(0x04)
        XCTAssertEqual(masks, [0x08, 0x40, 0x04])
        XCTAssertTrue(writes.allSatisfy { $0.focus == 1 })
        XCTAssertTrue(writes.allSatisfy { $0.state == desired })
    }

    func testWritesModeFirstThenPerLed() throws {
        let expected = state(mode: 0)
        let desired = state(mode: 2, leds: [.baselineOff, .baselineOff, .baselineOff, solid(15)])
        let writes = try DialLedControl.writes(desired: desired, expected: expected)
        XCTAssertEqual(writes.first?.mask, DialLedControl.FieldMask.mode)
        XCTAssertEqual(writes.last?.mask, DialLedControl.FieldMask.workType)
        XCTAssertEqual(writes.last?.focus, 3)
    }

    func testBrightnessOnlyBlinkIsSingleFrame() throws {
        // R1: blinking toggles brightness only — one mask-0x40 frame, no
        // workType/workTime rewrite.
        let lit = state(leds: [.baselineOff, .baselineOff, .baselineOff, solid(15)])
        let dark = state(leds: [.baselineOff, .baselineOff, .baselineOff, solid(0)])
        let writes = try DialLedControl.writes(desired: dark, expected: lit)
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes[0].mask, DialLedControl.FieldMask.alwaysOnBrightness)
        XCTAssertEqual(writes[0].focus, 3)
    }

    func testWritesRejectInvalidDesiredBeforeAnythingElse() {
        var leds = state().leds
        leds[1].workType = 5
        XCTAssertThrowsError(
            try DialLedControl.writes(desired: state(leds: leds), expected: state())
        )
    }

    // MARK: - Response parsing

    func testParseStateFromKnownGetResponse() throws {
        // Layout captured from the device on 2026-11-19 (baseline).
        var plaintext = [UInt8](repeating: 0, count: 64)
        plaintext[0] = 0x81; plaintext[1] = 0x0B; plaintext[2] = 0x88; plaintext[3] = 0x11
        plaintext[6] = 2; plaintext[7] = 7
        let tuples: [[UInt8]] = [
            [2, 10, 2, 7, 7], [0, 10, 2, 7, 7], [0, 10, 2, 7, 7], [1, 10, 2, 7, 7],
        ]
        for (index, tuple) in tuples.enumerated() {
            for (offset, byte) in tuple.enumerated() {
                plaintext[8 + 5 * index + offset] = byte
            }
        }
        let parsed = DialLedControl.parseState(fromPlaintext: plaintext)
        XCTAssertEqual(parsed, .baseline)
    }

    func testParseStateRejectsWrongHeader() {
        var plaintext = [UInt8](repeating: 0, count: 64)
        plaintext[0] = 0x81; plaintext[1] = 0x0B; plaintext[2] = 0x88; plaintext[3] = 0x11
        XCTAssertNil(DialLedControl.parseState(fromPlaintext: Array(plaintext.prefix(20))))
        plaintext[3] = 0x14
        XCTAssertNil(DialLedControl.parseState(fromPlaintext: plaintext))
    }

    func testWriteAckMatching() {
        let write = DialLedControl.Write(
            mask: 0x40, focus: 3, state: state()
        )
        var ack = [UInt8](repeating: 0, count: 64)
        ack[0] = 0x81; ack[1] = 0x0B; ack[2] = 0x88; ack[3] = 0x14
        ack[4] = 0x40; ack[5] = 3
        XCTAssertTrue(DialLedControl.isWriteAck(plaintext: ack, for: write))
        ack[5] = 2
        XCTAssertFalse(DialLedControl.isWriteAck(plaintext: ack, for: write))
        ack[3] = 0x11
        XCTAssertFalse(DialLedControl.isWriteAck(plaintext: ack, for: write))
    }
}