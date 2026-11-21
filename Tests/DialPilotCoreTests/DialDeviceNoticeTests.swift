import XCTest
@testable import DialPilotCore

final class DialDeviceNoticeTests: XCTestCase {
    func testParsesStandbyNoticeAndPreservesRawStatus() {
        XCTAssertEqual(
            DialDeviceNoticeParser.parse(plaintext: [0x0B, 0x0D, 0x00]),
            .standby(status: 0x00)
        )
        XCTAssertEqual(
            DialDeviceNoticeParser.parse(plaintext: [0x8B, 0x0D, 0x7F]),
            .standby(status: 0x7F)
        )
    }

    func testDeviceActiveUsesOnlyLowBit() {
        XCTAssertEqual(
            DialDeviceNoticeParser.parse(plaintext: [0x0B, 0x0B, 0xA4]),
            .deviceActive(isActive: false)
        )
        XCTAssertEqual(
            DialDeviceNoticeParser.parse(plaintext: [0xCB, 0x0B, 0xA5]),
            .deviceActive(isActive: true)
        )
    }

    func testParsesPayloadFreePowerOnNotice() {
        XCTAssertEqual(
            DialDeviceNoticeParser.parse(plaintext: [0x0B, 0xF0]),
            .powerOn
        )
    }

    func testParsesEncryptedReport() throws {
        var plaintext = [UInt8](repeating: 0, count: 64)
        plaintext.replaceSubrange(0..<3, with: [0x8B, 0x0D, 0x02])
        let report = try DialPacketCodec.encrypt(plaintext)

        XCTAssertEqual(
            DialDeviceNoticeParser.parse(
                reportID: UInt32(DialPacketCodec.reportID),
                report: report
            ),
            .standby(status: 0x02)
        )
    }

    func testAcceptsReportIDInsideBufferWhenCallbackReportsZero() throws {
        var plaintext = [UInt8](repeating: 0, count: 64)
        plaintext.replaceSubrange(0..<3, with: [0x0B, 0x0B, 0x03])
        let encrypted = try DialPacketCodec.encrypt(plaintext)
        let report = [DialPacketCodec.reportID] + encrypted.prefix(63)

        XCTAssertEqual(
            DialDeviceNoticeParser.parse(reportID: 0, report: Array(report)),
            .deviceActive(isActive: true)
        )
    }

    func testRejectsWrongGroupSubtypeTruncatedPayloadAndReportID() throws {
        XCTAssertNil(DialDeviceNoticeParser.parse(plaintext: [0x0A, 0x0D, 1]))
        XCTAssertNil(DialDeviceNoticeParser.parse(plaintext: [0x0B, 0x10, 1]))
        XCTAssertNil(DialDeviceNoticeParser.parse(plaintext: [0x0B, 0x0D]))
        XCTAssertNil(DialDeviceNoticeParser.parse(plaintext: [0x0B, 0x0B]))

        let encrypted = try DialPacketCodec.encrypt(
            [0x0B, 0xF0] + [UInt8](repeating: 0, count: 62)
        )
        XCTAssertNil(DialDeviceNoticeParser.parse(reportID: 0x54, report: encrypted))
    }
}
