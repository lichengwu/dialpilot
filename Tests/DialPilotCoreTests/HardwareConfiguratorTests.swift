import XCTest
@testable import DialPilotCore

final class HardwareConfiguratorTests: XCTestCase {
    func testKnownHIDDescriptor() {
        XCTAssertEqual(DialHIDDescriptor.vibeKey.vendorID, 0xFFF1)
        XCTAssertEqual(DialHIDDescriptor.vibeKey.productID, 0x00DD)
        XCTAssertEqual(DialHIDDescriptor.vibeKey.usagePage, 0xFFFC)
        XCTAssertEqual(DialHIDDescriptor.vibeKey.reportID, 0x55)
        XCTAssertEqual(DialHIDDescriptor.vibeKey.reportLength, 64)
    }

    func testProtocolCanBeReplacedWithRecordingMock() throws {
        final class RecordingConfigurator: HardwareConfigurator {
            var appliedProfiles: [ProfileConfiguration] = []

            func apply(profile: ProfileConfiguration) throws {
                appliedProfiles.append(profile)
            }
        }

        let mock = RecordingConfigurator()
        let profile = AppConfiguration.default.profileA
        try mock.apply(profile: profile)

        XCTAssertEqual(mock.appliedProfiles, [profile])
    }

    func testNativeProfileUsesDeviceStorageOrder() {
        let bindings = AppConfiguration.default.profileA.indexedControlBindings

        XCTAssertEqual(bindings.map(\.index), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(
            bindings.map(\.control),
            [.topButton, .middleButton, .bottomButton, .knobPress, .knobRight, .knobLeft]
        )
        XCTAssertEqual(bindings[3].binding, .preset(.selectAll))
        XCTAssertFalse(bindings.contains { $0.control == .knobDoublePress })
    }
}
