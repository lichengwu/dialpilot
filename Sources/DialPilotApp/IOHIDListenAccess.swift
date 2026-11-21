import Foundation
import IOKit.hid
import DialPilotCore

enum IOHIDListenAccessError: LocalizedError {
    case denied
    case permissionRequired

    var errorDescription: String? {
        switch self {
        case .denied:
            L10n.text(.errInputDenied)
        case .permissionRequired:
            L10n.text(.errInputPrompt)
        }
    }
}

enum IOHIDListenAccess {
    static var isGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    static func ensure(promptForPermission: Bool) throws {
        let requestType = kIOHIDRequestTypeListenEvent
        switch IOHIDCheckAccess(requestType) {
        case kIOHIDAccessTypeGranted:
            return
        case kIOHIDAccessTypeDenied:
            throw IOHIDListenAccessError.denied
        case kIOHIDAccessTypeUnknown:
            guard promptForPermission,
                  IOHIDRequestAccess(requestType),
                  IOHIDCheckAccess(requestType) == kIOHIDAccessTypeGranted else {
                throw IOHIDListenAccessError.permissionRequired
            }
        default:
            throw IOHIDListenAccessError.permissionRequired
        }
    }
}
