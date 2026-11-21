import Foundation

/// AU05 accepts one encrypted output report at a time. Keep every profile
/// write on one queue so rapid UI changes cannot overlap reports.
enum HIDOutputSerialQueue {
    static let queue = DispatchQueue(label: "dev.lichengwu.dialpilot.hid-output")
}
