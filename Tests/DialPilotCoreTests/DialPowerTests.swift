import XCTest
@testable import DialPilotCore

final class DialPowerTests: XCTestCase {
    func testReadOnlyPowerQueryPlaintextsMatchVendorBuilders() {
        let expectedHeaders: [(DialPowerQuery, [UInt8])] = [
            (.battery, [0x01, 0x01, 0x02, 0x01]),
            (.standbyStatus, [0x01, 0x01, 0x0D, 0x01]),
            (.standbyTime, [0x01, 0x01, 0x2C, 0x01]),
            (.sleepTime, [0x01, 0x01, 0x42, 0x01])
        ]

        for (query, expectedHeader) in expectedHeaders {
            let plaintext = DialPacketCodec.powerQueryPlaintext(query)
            XCTAssertEqual(plaintext.count, 64)
            XCTAssertEqual(Array(plaintext.prefix(4)), expectedHeader)
            XCTAssertTrue(plaintext.dropFirst(4).allSatisfy { $0 == 0 })
        }
    }

    func testPowerQueryReportsUseAU05EncryptedReportFraming() throws {
        for query in DialPowerQuery.allCases {
            let report = try DialPacketCodec.powerQueryReport(query)
            XCTAssertEqual(report.count, 64)
            XCTAssertEqual(report.first, DialPacketCodec.reportID)

            let decrypted = try DialPacketCodec.decryptInputReport(report)
            XCTAssertEqual(
                Array(decrypted.prefix(4)),
                Array(DialPacketCodec.powerQueryPlaintext(query).prefix(4))
            )
        }
    }

    func testParsesBatteryPercentageVoltageAndFlags() throws {
        var plaintext = response(commandID: 0x02)
        plaintext.replaceSubrange(
            4..<12,
            with: [0x68, 0x0E, 0x1E, 0x00, 0xE3, 0x01, 0x01, 0x0B]
        )

        XCTAssertEqual(
            try parse(plaintext),
            .battery(DialBatteryStatus(
                percent: 30,
                voltageMillivolts: 3688,
                isCharging: true,
                isFullyCharged: true,
                lowBatteryLevel: 3,
                isPoweredOff: false
            ))
        )
    }

    func testParsesObservedStandbyAndSleepValues() throws {
        var standbyStatus = response(commandID: 0x0D)
        standbyStatus[4] = 0
        XCTAssertEqual(
            try parse(standbyStatus),
            .standbyStatus(isStandby: false)
        )

        var standbyTime = response(commandID: 0x2C)
        standbyTime.replaceSubrange(4..<8, with: [0x2C, 0x01, 0x00, 0x00])
        XCTAssertEqual(try parse(standbyTime), .standbyTime(seconds: 300))

        var sleepTime = response(commandID: 0x42)
        sleepTime.replaceSubrange(4..<8, with: [0x10, 0x0E, 0x00, 0x00])
        XCTAssertEqual(try parse(sleepTime), .sleepTime(seconds: 3_600))
    }

    func testAcceptsReportIDInsideBufferWhenCallbackReportsZero() throws {
        var plaintext = response(commandID: 0x2C)
        plaintext.replaceSubrange(4..<8, with: [0x2C, 0x01, 0x00, 0x00])
        let encrypted = try DialPacketCodec.encrypt(plaintext)
        let report = [DialPacketCodec.reportID] + encrypted.prefix(63)

        XCTAssertEqual(
            DialPowerResponseParser.parse(reportID: 0, report: Array(report)),
            .standbyTime(seconds: 300)
        )
    }

    func testSnapshotAccumulatesIndependentResponses() {
        let battery = DialBatteryStatus(
            percent: 30,
            voltageMillivolts: 3688,
            isCharging: false,
            isFullyCharged: false,
            lowBatteryLevel: 0,
            isPoweredOff: false
        )
        var snapshot = DialPowerSnapshot()

        snapshot.apply(.battery(battery))
        snapshot.apply(.standbyStatus(isStandby: false))
        snapshot.apply(.standbyTime(seconds: 300))
        snapshot.apply(.sleepTime(seconds: 3_600))

        XCTAssertEqual(snapshot.battery, battery)
        XCTAssertEqual(snapshot.isStandby, false)
        XCTAssertEqual(snapshot.standbyTimeSeconds, 300)
        XCTAssertEqual(snapshot.sleepTimeSeconds, 3_600)
    }

    func testRejectsRequestsUnknownCommandsInvalidStatusAndWrongReportID() throws {
        var request = response(commandID: 0x2C)
        request[3] = 0x01
        XCTAssertNil(DialPowerResponseParser.parse(plaintext: request))

        XCTAssertNil(DialPowerResponseParser.parse(
            plaintext: response(commandID: 0x7F)
        ))

        var invalidStatus = response(commandID: 0x0D)
        invalidStatus[4] = 2
        XCTAssertNil(DialPowerResponseParser.parse(plaintext: invalidStatus))

        let encrypted = try DialPacketCodec.encrypt(response(commandID: 0x42))
        XCTAssertNil(DialPowerResponseParser.parse(reportID: 0x54, report: encrypted))
    }

    func testRejectsFailedResponseAndImpossibleBatteryPercentage() {
        var failedResponse = response(commandID: 0x2C)
        failedResponse[3] = 0x10
        XCTAssertNil(DialPowerResponseParser.parse(plaintext: failedResponse))

        var impossibleBattery = response(commandID: 0x02)
        impossibleBattery[6] = 101
        XCTAssertNil(DialPowerResponseParser.parse(plaintext: impossibleBattery))
    }

    private func response(commandID: UInt8) -> [UInt8] {
        var plaintext = [UInt8](repeating: 0, count: 64)
        plaintext.replaceSubrange(0..<4, with: [0x81, 0x01, commandID, 0x11])
        return plaintext
    }

    private func parse(_ plaintext: [UInt8]) throws -> DialPowerResponse? {
        let report = try DialPacketCodec.encrypt(plaintext)
        return DialPowerResponseParser.parse(
            reportID: UInt32(DialPacketCodec.reportID),
            report: report
        )
    }
}
