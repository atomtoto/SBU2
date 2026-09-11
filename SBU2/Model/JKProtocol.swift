//
//  JKProtocol.swift
//  SBU2
//
//  The JK (Jikong) BLE wire format, read side only.
//
//  Checked against the ESPHome `jk_bms_ble` component, which is the reference
//  implementation for this family, and against the captured frames it carries in
//  its own comments — every offset below was read back out of one of those frames
//  before it was written down here.
//

import Foundation

/// JK's framing, and the two frames worth decoding.
///
/// Almost nothing here resembles JBD. JK sends fixed 300-byte frames rather than
/// length-prefixed ones, puts its multi-byte figures in little-endian order rather
/// than big-endian, and answers a request by streaming until told otherwise. The one
/// thing the two families share is the checksum: a plain 8-bit sum, whatever either
/// vendor calls it.
enum JK {

    // MARK: - Framing

    /// Every answer opens with this. The request uses a *different* order of the same
    /// four bytes, which is not a mistake in either direction — see `request`.
    static let preamble: [UInt8] = [0x55, 0xAA, 0xEB, 0x90]

    /// Answers are this long. A pack may send more — the firmware pads to 320 on some
    /// versions — but the checksum is at 299 either way, so everything past it is
    /// ignored and dropped at the next preamble.
    static let frameLength = 300

    /// The byte at index 4 says which frame this is.
    enum FrameType: UInt8 {
        case settings = 0x01
        case cellInfo = 0x02
        case deviceInfo = 0x03
    }

    /// The register a request asks for. The pack answers with the matching frame type.
    enum Command: UInt8 {
        case cellInfo = 0x96
        case deviceInfo = 0x97

        var answers: FrameType {
            switch self {
            case .cellInfo: .cellInfo
            case .deviceInfo: .deviceInfo
            }
        }
    }

    /// The holding registers worth writing to. Both take a four-byte value that is
    /// one or zero, and neither is a stored setting — they are the terminals
    /// themselves, which is why they are the only writes this family offers.
    enum Register: UInt8 {
        case chargingSwitch = 0x1D
        case dischargingSwitch = 0x1E
    }

    /// A sum of bytes truncated to eight bits. Not a CRC, despite the name it goes by
    /// in every implementation of this protocol.
    static func checksum<Bytes: Sequence>(_ bytes: Bytes) -> UInt8 where Bytes.Element == UInt8 {
        bytes.reduce(into: UInt8(0)) { $0 = $0 &+ $1 }
    }

    /// The twenty-byte request: preamble, register, the length of the value, the value
    /// itself little-endian, padding, and the sum of everything before it.
    ///
    /// Reads carry no value, so all that is left of it is zeros — but the length byte
    /// and the four value bytes are still part of the frame and still counted into the
    /// checksum, so they are written out rather than left implied.
    static func frame(address: UInt8, value: UInt32 = 0, valueLength: UInt8 = 0) -> [UInt8] {
        var frame = [UInt8](repeating: 0, count: 20)
        frame[0] = 0xAA
        frame[1] = 0x55
        frame[2] = 0x90
        frame[3] = 0xEB
        frame[4] = address
        frame[5] = valueLength
        frame[6] = UInt8(truncatingIfNeeded: value)
        frame[7] = UInt8(truncatingIfNeeded: value >> 8)
        frame[8] = UInt8(truncatingIfNeeded: value >> 16)
        frame[9] = UInt8(truncatingIfNeeded: value >> 24)
        frame[19] = checksum(frame[0..<19])
        return frame
    }

    /// Asks for one of the two frames worth reading. Carries no value.
    static func request(_ command: Command) -> [UInt8] {
        frame(address: command.rawValue)
    }

    /// Opens or closes one of the terminals. The value is four bytes wide even though
    /// only its lowest bit means anything, which is what the reference writes.
    static func write(_ register: Register, on: Bool) -> [UInt8] {
        frame(address: register.rawValue, value: on ? 1 : 0, valueLength: 4)
    }

    // MARK: - Which layout the pack is speaking

    /// How many cells the frame makes room for, which moves everything after them.
    ///
    /// The packs that take more than 24 cells push the fields that follow the cell
    /// voltages along by sixteen bytes, and the fields after the cell *resistances*
    /// by thirty-two — the shift doubles halfway down the frame because both the
    /// voltage block and the resistance block grew.
    enum Variant: String, CaseIterable {
        case cells24, cells32

        var cellCount: Int { self == .cells24 ? 24 : 32 }
        /// The shift that applies between the cell voltages and the resistances.
        var shift: Int { self == .cells24 ? 0 : 16 }
        /// The shift that applies from the resistances onward.
        var lateShift: Int { shift * 2 }
    }

    /// Which layout this frame is in, or `nil` if it is not recognisably either.
    ///
    /// The reference implementation makes this something the user has to configure
    /// and get right. It does not have to be: the frame carries the pack's own
    /// average cell voltage, at a position that moves with the layout, so the layout
    /// whose average agrees with the mean of the cells it just decoded is the layout
    /// the pack is speaking. Read the wrong way round, that field lands in a cell
    /// voltage or a resistance and the two disagree by volts.
    static func variant(ofCellInfo frame: [UInt8]) -> Variant? {
        Variant.allCases.first { isSelfConsistent(frame, as: $0) }
    }

    private static func isSelfConsistent(_ frame: [UInt8], as variant: Variant) -> Bool {
        guard frame.count >= frameLength else { return false }
        let live = cellVoltages(frame, variant).filter { $0 > 0 }
        guard !live.isEmpty else { return false }

        let reported = Double(uint16(frame, 58 + variant.shift)) / 1000
        guard reported > 0 else { return false }

        let mean = live.reduce(0, +) / Double(live.count)
        // The pack averages the same cells the same way, so agreement is to within
        // its own rounding. Ten millivolts is far tighter than the volts a
        // misread layout is out by, and far looser than that rounding.
        return abs(mean - reported) < 0.01
    }

    // MARK: - Cell information

    /// Every cell the layout makes room for, in volts. Unpopulated ones read zero,
    /// which is what the rest of the app already expects.
    static func cellVoltages(_ frame: [UInt8], _ variant: Variant) -> [Double] {
        guard frame.count >= frameLength else { return [] }
        return (0..<variant.cellCount).map { Double(uint16(frame, 6 + $0 * 2)) / 1000 }
    }

    /// The readings the overview is built from.
    ///
    /// The software version and the production date are not in this frame — they come
    /// from the device-information frame, and the adapter stamps them on afterwards.
    static func decodeCellInfo(_ frame: [UInt8], _ variant: Variant) -> BasicInfo? {
        guard frame.count >= frameLength else { return nil }
        let late = variant.lateShift

        var info = BasicInfo()
        info.packVoltage = Double(uint32(frame, 118 + late)) / 1000
        info.current = Double(int32(frame, 126 + late)) / 1000
        info.stateOfCharge = Int(frame[141 + late])
        info.residualCapacity = Double(uint32(frame, 142 + late)) / 1000
        info.nominalCapacity = Double(uint32(frame, 146 + late)) / 1000
        info.cycles = Int(uint32(frame, 150 + late))
        info.chargeMOSEnabled = frame[166 + late] != 0
        info.dischargeMOSEnabled = frame[167 + late] != 0
        info.cellCount = cellVoltages(frame, variant).filter { $0 > 0 }.count
        info.temperatures = temperatures(frame, variant)
        info.protections = protections(faults(frame, variant))
        // JK reports that the balancer is working and how much it is moving, but not
        // which cell it is working on, so nothing can be filled in here.
        info.balancingCells = []
        return info
    }

    /// The two probes and the MOSFET sensor, in the order the pack numbers them.
    ///
    /// The longer layout moves the MOSFET sensor out of the way of a fault bitmask
    /// that grew from sixteen bits to thirty-two and took its place.
    private static func temperatures(_ frame: [UInt8], _ variant: Variant) -> [Double] {
        let late = variant.lateShift
        let mosfet = variant == .cells32 ? 112 + late : 134 + late
        return [Double(int16(frame, 130 + late)) / 10,
                Double(int16(frame, 132 + late)) / 10,
                Double(int16(frame, mosfet)) / 10]
    }

    /// The fault bitmask, which is sixteen bits on the shorter layout and thirty-two
    /// on the longer one — and in a different place, since the extra sixteen bits had
    /// to come from somewhere.
    static func faults(_ frame: [UInt8], _ variant: Variant) -> UInt32 {
        let late = variant.lateShift
        return variant == .cells32
            ? uint32(frame, 134 + late)
            : UInt32(uint16(frame, 136 + late))
    }

    /// The JK fault bits that mean the same thing one of ours does.
    ///
    /// Their table is longer than ours and is not a superset of it. Several JK faults
    /// have no counterpart here — wire resistance, a cell count that disagrees with
    /// the settings, a coprocessor that has stopped answering — and are not shown
    /// rather than being forced into an approximation. In the other direction, and
    /// more surprisingly, JK's table has no cell-overvoltage bit at all: bit 4 is
    /// "battery is fully charged", which is not a fault. So that one protection can
    /// never light up on a JK pack, and its absence is not evidence of anything.
    private static let protectionBits: [(bit: UInt32, protection: Protection)] = [
        (5, .packOverVoltage),
        (6, .chargeOverCurrent),
        (7, .shortCircuit),
        (8, .chargeOverTemperature),
        (9, .chargeUnderTemperature),
        (10, .frontEndError),          // Coprocessor communication error
        (11, .cellUnderVoltage),
        (12, .packUnderVoltage),
        (13, .dischargeOverCurrent),
        (14, .shortCircuit),
        (15, .dischargeOverTemperature),
        (16, .frontEndError),          // Charging MOSFET abnormal
        (17, .frontEndError),          // Discharging MOSFET abnormal
        (22, .frontEndError),          // Temperature sensor anomaly
        (27, .dischargeUnderTemperature)
    ]

    static func protections(_ faults: UInt32) -> Set<Protection> {
        Set(protectionBits.filter { faults >> $0.bit & 1 == 1 }.map(\.protection))
    }

    // MARK: - Device information

    /// What the pack calls itself, and when it was built.
    struct Identity: Equatable {
        var model = ""
        var hardwareVersion = ""
        var softwareVersion = ""
        var productionDate: Date?
    }

    static func decodeDeviceInfo(_ frame: [UInt8]) -> Identity? {
        guard frame.count >= frameLength else { return nil }
        var identity = Identity()
        identity.model = string(frame, at: 6, length: 16)
        identity.hardwareVersion = string(frame, at: 22, length: 8)
        identity.softwareVersion = string(frame, at: 30, length: 8)
        identity.productionDate = productionDate(string(frame, at: 78, length: 6))
        return identity
    }

    /// Six ASCII digits, `YYMMDD`, with the century left off. Empty on the packs that
    /// never recorded one.
    static func productionDate(_ text: String) -> Date? {
        guard text.count == 6, text.allSatisfy(\.isNumber),
              let year = Int(text.prefix(2)),
              let month = Int(text.dropFirst(2).prefix(2)),
              let day = Int(text.dropFirst(4).prefix(2)),
              month > 0, day > 0
        else { return nil }
        var components = DateComponents()
        components.year = 2000 + year
        components.month = month
        components.day = day
        return Calendar(identifier: .gregorian).date(from: components)
    }

    // MARK: - Reading the frame

    /// JK is little-endian throughout. JBD is big-endian throughout. Nothing about
    /// either is negotiable, and mixing them up produces figures that look almost
    /// plausible, which is the dangerous kind of wrong.
    private static func uint16(_ frame: [UInt8], _ index: Int) -> UInt16 {
        UInt16(frame[index]) | UInt16(frame[index + 1]) << 8
    }

    private static func int16(_ frame: [UInt8], _ index: Int) -> Int16 {
        Int16(bitPattern: uint16(frame, index))
    }

    private static func uint32(_ frame: [UInt8], _ index: Int) -> UInt32 {
        UInt32(uint16(frame, index)) | UInt32(uint16(frame, index + 2)) << 16
    }

    private static func int32(_ frame: [UInt8], _ index: Int) -> Int32 {
        Int32(bitPattern: uint32(frame, index))
    }

    /// A fixed-width ASCII field, cut at its first zero.
    private static func string(_ frame: [UInt8], at start: Int, length: Int) -> String {
        guard start < frame.count else { return "" }
        let field = frame[start..<min(start + length, frame.count)]
        return String(decoding: field.prefix { $0 != 0 }, as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Reassembly

/// Rebuilds JK's fixed-length frames from the twenty-byte notifications they arrive in.
///
/// `FrameAssembler` cannot do this job: it cuts frames at a length the header
/// announces, and JK announces nothing — every frame is the same size, delimited only
/// by a four-byte preamble at the front and validated by a sum at the end.
struct JKFrameAssembler {

    /// How long a half-received frame may sit at the head of the buffer. A JK frame
    /// takes fifteen notifications, so this has to be generous enough for a slow link
    /// to finish one, and short enough that a truncated one does not block the next.
    static let staleAfter: TimeInterval = 2.0

    private var buffer: [UInt8] = []
    private var partialSince: Date?

    mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
        partialSince = nil
    }

    mutating func append(_ data: Data, at now: Date = .now) -> [[UInt8]] {
        if let partialSince, now.timeIntervalSince(partialSince) > Self.staleAfter {
            reset()
        }
        buffer.append(contentsOf: data)

        var frames: [[UInt8]] = []
        while true {
            guard let start = firstPreamble() else {
                // A preamble could be straddling the end of what has arrived, so the
                // last three bytes are kept and everything before them dropped.
                if buffer.count > 3 { buffer.removeFirst(buffer.count - 3) }
                break
            }
            if start > 0 { buffer.removeFirst(start) }
            guard buffer.count >= JK.frameLength else { break }

            let frame = Array(buffer[0..<JK.frameLength])
            if JK.checksum(frame[0..<(JK.frameLength - 1)]) == frame[JK.frameLength - 1] {
                frames.append(frame)
                buffer.removeFirst(JK.frameLength)
            } else {
                // Either the preamble was really four bytes of payload, or the frame
                // was corrupted. Step past it and look for the next one.
                buffer.removeFirst(JK.preamble.count)
            }
        }

        partialSince = buffer.isEmpty ? nil : (partialSince ?? now)
        return frames
    }

    private func firstPreamble() -> Int? {
        guard buffer.count >= JK.preamble.count else { return nil }
        let last = buffer.count - JK.preamble.count
        // Compared in place rather than by slicing: this runs over the whole buffer
        // on every one of the fifteen notifications a frame arrives in.
        outer: for index in 0...last {
            for offset in 0..<JK.preamble.count where buffer[index + offset] != JK.preamble[offset] {
                continue outer
            }
            return index
        }
        return nil
    }
}
