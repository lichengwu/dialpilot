// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DialPilot",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DialPilot", targets: ["DialPilotApp"]),
        .executable(name: "dialpilotctl", targets: ["dialpilotctl"]),
        .library(name: "DialPilotCore", targets: ["DialPilotCore"])
    ],
    targets: [
        // Pure logic: protocol codec, LED engine, installers, arbitration.
        // No AppKit / IOKit imports here — everything is unit-testable.
        .target(name: "DialPilotCore"),
        // Menu-bar app: HID transport, timers, UI. Thin shells over Core.
        .executableTarget(
            name: "DialPilotApp",
            dependencies: ["DialPilotCore"]
        ),
        // Hook CLI: forwards agent events to the resident app over a Unix
        // socket. Never touches HID itself (single-writer discipline).
        .executableTarget(
            name: "dialpilotctl",
            dependencies: ["DialPilotCore"]
        ),
        .testTarget(
            name: "DialPilotCoreTests",
            dependencies: ["DialPilotCore"]
        ),
        .testTarget(
            name: "DialPilotAppTests",
            dependencies: ["DialPilotApp"]
        )
    ]
)