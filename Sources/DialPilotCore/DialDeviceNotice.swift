import Foundation

/// Runtime notices emitted by the AU05. These values are parsed from input
/// reports only; this type does not construct or send device commands.
public enum DialDeviceNotice: Equatable, Sendable {
    /// The vendor callback preserves the raw status byte. Consumers that need
    /// a Boolean should treat any nonzero value as standby.
    case standby(status: UInt8)
    /// The vendor parser defines active as bit 0 and ignores the other bits.
    case deviceActive(isActive: Bool)
    /// The vendor power-on notice has no payload beyond subtype 0xF0.
    case powerOn
}

public enum DialDeviceNoticeParser {
    public static func parse(reportID: UInt32, report: [UInt8]) -> DialDeviceNotice? {
        let carriesReportID = reportID == UInt32(DialPacketCodec.reportID)
            || (reportID == 0 && report.first == DialPacketCodec.reportID)
        guard carriesReportID,
              let plaintext = try? DialPacketCodec.decryptInputReport(report) else {
            return nil
        }
        return parse(plaintext: plaintext)
    }

    public static func parse(plaintext: [UInt8]) -> DialDeviceNotice? {
        guard plaintext.count >= 2,
              (plaintext[0] & 0x1F) == 0x0B else {
            return nil
        }

        switch plaintext[1] {
        case 0x0D:
            guard plaintext.count >= 3 else { return nil }
            return .standby(status: plaintext[2])

        case 0x0B:
            guard plaintext.count >= 3 else { return nil }
            return .deviceActive(isActive: (plaintext[2] & 0x01) != 0)

        case 0xF0:
            return .powerOn

        default:
            return nil
        }
    }
}
