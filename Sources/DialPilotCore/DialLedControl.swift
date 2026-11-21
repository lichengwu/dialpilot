import Foundation

// ─────────────────────────────────────────────────────────────────────────
// HARD-WON PITFALLS (docs/protocol.md §Indicator LED commands). Read before
// changing anything here — each cost a debugging session on real hardware:
//
// 1. workTime is the per-LED RENDER GATE. Factory workTime=10 makes a light
//    auto-extinguish after ~10 s; sustained solid light REQUIRES workTime=255
//    written via a dedicated mask-0x08 frame. Missing this once looked like
//    "LEDs never render at all".
// 2. GET readback echoes STALE workTime values — never trust the read-back
//    time field; judge by observed behavior (lit? for how long?).
// 3. The firmware only renders on a NEW write. Re-sending an identical table
//    is a no-op; state changes must produce at least one changed field, or
//    use the force path (re-send activation fields workTime→workType).
// 4. Breathing (workType=2) does NOT render on this firmware revision even
//    with valid levels/brightness — simulate it with brightness-toggle
//    blinking (see DialLedPattern). Global mode 1 (all-on) DOES light all
//    four LEDs, proving the voice-key LED hardware is fine.
// 5. LED 0 (voice key) is firmware-driven key feedback: solid/breathe writes
//    never render it; it only joins global all-on. The host renderer must
//    preserve its stored tuple and never try to drive it.
// 6. SET command is 0x88 in group 0x0B — an earlier 0x48 note belonged to a
//    different product (DialMini). Verified byte-by-byte against the vendor
//    host disassembly; do not "fix" it back.
// 7. Full-payload SET frames (all four LED tuples) DO render; an earlier
//    "only single-LED frames work" conclusion was wrong (masked by pitfall 1).
// ─────────────────────────────────────────────────────────────────────────

/// One AU05 indicator LED tuple as stored by the firmware.
/// Field order matches the wire layout: type, workTime, breatheLevel,
/// breatheBrightness, alwaysOnBrightness.
public struct DialLedTuple: Equatable, Sendable {
    public var workType: UInt8
    public var workTime: UInt8
    public var breatheLevel: UInt8
    public var breatheBrightness: UInt8
    public var alwaysOnBrightness: UInt8

    public init(
        workType: UInt8,
        workTime: UInt8,
        breatheLevel: UInt8,
        breatheBrightness: UInt8,
        alwaysOnBrightness: UInt8
    ) {
        self.workType = workType
        self.workTime = workTime
        self.breatheLevel = breatheLevel
        self.breatheBrightness = breatheBrightness
        self.alwaysOnBrightness = alwaysOnBrightness
    }

    public var bytes: [UInt8] {
        [workType, workTime, breatheLevel, breatheBrightness, alwaysOnBrightness]
    }

    /// The factory baseline tuple used for slots the host does not drive.
    public static let baselineOff = DialLedTuple(
        workType: 0, workTime: 10, breatheLevel: 2,
        breatheBrightness: 7, alwaysOnBrightness: 7
    )
}

/// Full four-LED lighting state. Index map (hardware-verified):
/// 0 = voice key (firmware-driven, never written by the host renderer),
/// 1 = middle key, 2 = bottom key, 3 = knob.
public struct DialLedState: Equatable, Sendable {
    public var mode: UInt8
    public var allOnBrightness: UInt8
    public var leds: [DialLedTuple]

    public init(mode: UInt8, allOnBrightness: UInt8, leds: [DialLedTuple]) {
        self.mode = mode
        self.allOnBrightness = allOnBrightness
        self.leds = leds
    }

    /// The device baseline observed before any host lighting writes.
    public static let baseline = DialLedState(
        mode: 2,
        allOnBrightness: 7,
        leds: [
            DialLedTuple(workType: 2, workTime: 10, breatheLevel: 2,
                            breatheBrightness: 7, alwaysOnBrightness: 7),
            .baselineOff,
            .baselineOff,
            DialLedTuple(workType: 1, workTime: 10, breatheLevel: 2,
                            breatheBrightness: 7, alwaysOnBrightness: 7),
        ]
    )
}

public enum DialLedControlError: Error, Equatable, LocalizedError {
    case invalidLedCount(actual: Int)
    case invalidMode(UInt8)
    case invalidWorkType(led: Int, value: UInt8)
    case invalidBrightness(led: Int, value: UInt8)
    case invalidAllOnBrightness(UInt8)
    case invalidWorkTime(led: Int, value: UInt8)
    case invalidBreatheLevel(led: Int, value: UInt8)

    public var errorDescription: String? {
        switch self {
        case let .invalidLedCount(actual):
            "AU05 灯效必须包含 4 颗灯，当前是 \(actual)。"
        case let .invalidMode(value):
            "灯效模式只允许 0/1/2，收到 \(value)。"
        case let .invalidWorkType(led, value):
            "灯 \(led) 的 workType 只允许 0/1，收到 \(value)。"
        case let .invalidBrightness(led, value):
            "灯 \(led) 的亮度只允许 0...20，收到 \(value)。"
        case let .invalidAllOnBrightness(value):
            "全亮亮度只允许 0...20，收到 \(value)。"
        case let .invalidWorkTime(led, value):
            "灯 \(led) 的 workTime 只允许 10 或 255，收到 \(value)。"
        case let .invalidBreatheLevel(led, value):
            "灯 \(led) 的呼吸等级只允许 0...6，收到 \(value)。"
        }
    }
}

/// Pure functions for the AU05 `01 0b 88` lighting command group.
///
/// Hardware rules baked in here (docs/protocol.md):
/// - Every SET frame carries the complete four-LED record; the mask only
///   selects which field this write changes. Partial payloads get wiped.
/// - workTime gates rendering: 10 = auto-off after ~10 s, 255 = stay lit.
/// - Write order: workTime/breatheLevel first, brightness next, workType
///   last as the activation trigger.
/// - The host renderer only drives LEDs 1...3; LED 0 keeps its stored tuple.
public enum DialLedControl {
    public static let commandGroup: UInt8 = 0x0B
    public static let commandID: UInt8 = 0x88

    public enum FieldMask {
        public static let mode: UInt8 = 0x01
        public static let allOnBrightness: UInt8 = 0x02
        public static let workType: UInt8 = 0x04
        public static let workTime: UInt8 = 0x08
        public static let breatheLevel: UInt8 = 0x10
        public static let breatheBrightness: UInt8 = 0x20
        public static let alwaysOnBrightness: UInt8 = 0x40
    }

    /// GET request plaintext: `01 0b 88 01`.
    public static func readPlaintext() -> [UInt8] {
        var plaintext = [UInt8](repeating: 0, count: DialPacketCodec.packetLength)
        plaintext[0] = 0x01
        plaintext[1] = commandGroup
        plaintext[2] = commandID
        plaintext[3] = 0x01
        return plaintext
    }

    public static func readReport() throws -> [UInt8] {
        try DialPacketCodec.outputReport(encrypting: readPlaintext())
    }

    /// Validates the host-writable value domain. Unknown values are rejected
    /// before anything reaches the device (single-writer discipline: only the resident app writes HID).
    public static func validate(_ state: DialLedState) throws {
        guard state.leds.count == 4 else {
            throw DialLedControlError.invalidLedCount(actual: state.leds.count)
        }
        guard state.mode <= 2 else {
            throw DialLedControlError.invalidMode(state.mode)
        }
        guard state.allOnBrightness <= 20 else {
            throw DialLedControlError.invalidAllOnBrightness(state.allOnBrightness)
        }
        for (index, led) in state.leds.enumerated() {
            // LED 0 is firmware-driven; its stored tuple may hold workType 2
            // (breathe) from the factory baseline, so allow 0...2 there.
            let maxType: UInt8 = index == 0 ? 2 : 1
            guard led.workType <= maxType else {
                throw DialLedControlError.invalidWorkType(led: index, value: led.workType)
            }
            guard led.alwaysOnBrightness <= 20, led.breatheBrightness <= 20 else {
                throw DialLedControlError.invalidBrightness(
                    led: index,
                    value: max(led.alwaysOnBrightness, led.breatheBrightness)
                )
            }
            guard led.workTime == 10 || led.workTime == 255 else {
                throw DialLedControlError.invalidWorkTime(led: index, value: led.workTime)
            }
            guard led.breatheLevel <= 6 else {
                throw DialLedControlError.invalidBreatheLevel(led: index, value: led.breatheLevel)
            }
        }
    }

    /// One full-payload SET plaintext. The mask selects the changed field;
    /// all four LED tuples ride along so the firmware keeps the other slots.
    public static func setPlaintext(
        mask: UInt8,
        focus: UInt8,
        state: DialLedState
    ) -> [UInt8] {
        var plaintext: [UInt8] = [
            0x01, commandGroup, commandID, 0x04,
            mask, focus, state.mode, state.allOnBrightness,
        ]
        plaintext += state.leds.flatMap(\.bytes)
        plaintext += [UInt8](repeating: 0, count: DialPacketCodec.packetLength - plaintext.count)
        return plaintext
    }

    public static func setReport(
        mask: UInt8,
        focus: UInt8,
        state: DialLedState
    ) throws -> [UInt8] {
        try DialPacketCodec.outputReport(
            encrypting: setPlaintext(mask: mask, focus: focus, state: state)
        )
    }

    /// A single planned write: which field, which LED, and the full state
    /// snapshot the frame must carry.
    public struct Write: Equatable, Sendable {
        public var mask: UInt8
        public var focus: UInt8
        public var state: DialLedState

        public init(mask: UInt8, focus: UInt8, state: DialLedState) {
            self.mask = mask
            self.focus = focus
            self.state = state
        }
    }

    /// Diffs desired against expected and returns the ordered write sequence.
    /// Order: mode, allOnBrightness, then per LED workTime/breatheLevel →
    /// brightness → workType last (activation trigger). Each write carries the
    /// full desired state so intermediate frames never clear other slots.
    public static func writes(
        desired: DialLedState,
        expected: DialLedState
    ) throws -> [Write] {
        try validate(desired)
        guard expected.leds.count == 4 else {
            throw DialLedControlError.invalidLedCount(actual: expected.leds.count)
        }
        var writes: [Write] = []
        func append(_ mask: UInt8, _ focus: UInt8 = 0) {
            writes.append(Write(mask: mask, focus: focus, state: desired))
        }
        if desired.mode != expected.mode { append(FieldMask.mode) }
        if desired.allOnBrightness != expected.allOnBrightness {
            append(FieldMask.allOnBrightness)
        }
        for index in 0..<4 {
            let old = expected.leds[index]
            let new = desired.leds[index]
            if new.workTime != old.workTime { append(FieldMask.workTime, UInt8(index)) }
            if new.breatheLevel != old.breatheLevel { append(FieldMask.breatheLevel, UInt8(index)) }
            if new.breatheBrightness != old.breatheBrightness {
                append(FieldMask.breatheBrightness, UInt8(index))
            }
            if new.alwaysOnBrightness != old.alwaysOnBrightness {
                append(FieldMask.alwaysOnBrightness, UInt8(index))
            }
            if new.workType != old.workType { append(FieldMask.workType, UInt8(index)) }
        }
        return writes
    }

    /// Parses a decrypted `81 0b 88 11` GET response into a full state.
    public static func parseState(fromPlaintext plaintext: [UInt8]) -> DialLedState? {
        guard plaintext.count >= 28,
              plaintext[0] == 0x81,
              plaintext[1] == commandGroup,
              plaintext[2] == commandID,
              plaintext[3] == 0x11 else {
            return nil
        }
        let leds = (0..<4).map { index -> DialLedTuple in
            let base = 8 + 5 * index
            return DialLedTuple(
                workType: plaintext[base],
                workTime: plaintext[base + 1],
                breatheLevel: plaintext[base + 2],
                breatheBrightness: plaintext[base + 3],
                alwaysOnBrightness: plaintext[base + 4]
            )
        }
        return DialLedState(mode: plaintext[6], allOnBrightness: plaintext[7], leds: leds)
    }

    /// True when the decrypted frame is the write ACK for the given write.
    public static func isWriteAck(plaintext: [UInt8], for write: Write) -> Bool {
        guard plaintext.count >= 6,
              plaintext[0] == 0x81,
              plaintext[1] == commandGroup,
              plaintext[2] == commandID,
              plaintext[3] == 0x14 else {
            return false
        }
        return plaintext[4] == write.mask && plaintext[5] == write.focus
    }
}