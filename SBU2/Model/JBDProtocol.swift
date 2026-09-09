//
//  JBDProtocol.swift
//  SBU2
//
//  Frame encoding/decoding for JBD (a.k.a. Xiaoxiang) smart BMS.
//

import Foundation

/// A JBD frame looks the same in both directions:
///
///     0xDD  <register>  <status>  <length>  <payload…>  <checksum hi>  <checksum lo>  0x77
///
/// In a request the second byte is the direction (`0xA5` read / `0x5A` write) and
/// the third is the register. In a response the second byte echoes the register and
/// the third reports the result (`0x00` = OK, anything else = error).
///
/// The checksum covers the status and length bytes plus the payload:
/// `0x10000 - sum`, truncated to 16 bits.
enum JBD {

    static let startByte: UInt8 = 0xDD
    static let stopByte: UInt8 = 0x77
    static let readByte: UInt8 = 0xA5
    static let writeByte: UInt8 = 0x5A

    /// Smallest possible frame: start + register + status + length + checksum + stop.
    static let overhead = 7

    /// Where the register and the payload length sit in a frame.
    static let registerIndex = 2
    static let lengthIndex = 3

    /// The framing `FrameAssembler` needs to cut JBD answers out of the byte stream.
    static let frameLayout = FrameAssembler.Layout(startByte: startByte,
                                                   stopByte: stopByte,
                                                   overhead: overhead,
                                                   lengthIndex: lengthIndex)

    enum Register: UInt8 {
        case basicInfo = 0x03
        case cellVoltages = 0x04
        /// Enables factory ("read/write") mode. Needed before writing anything.
        case factoryModeOpen = 0x00
        /// Leaves factory mode and commits the changes.
        case factoryModeClose = 0x01
        /// Charge/discharge MOSFET control.
        case mosControl = 0xE1
        /// Unlocks a password-protected BMS for the rest of the session.
        case enterPassword = 0x06
        /// Sets or replaces the hardware password.
        case setPassword = 0x07
        /// Clears the hardware password.
        case clearPassword = 0x09
    }

    // MARK: - Requests

    /// `0x10000 - sum(bytes)`, truncated to 16 bits. The checksummed range starts at
    /// the register byte for a request and at the status byte for a response — both
    /// sit at the same offset, so the caller passes whichever applies.
    static func checksum(headerByte: UInt8, payload: [UInt8]) -> UInt16 {
        let sum = payload.reduce(UInt32(headerByte) + UInt32(payload.count)) { $0 + UInt32($1) }
        return UInt16(truncatingIfNeeded: 0x10000 &- sum)
    }

    private static func frame(direction: UInt8, register: UInt8, payload: [UInt8]) -> [UInt8] {
        let sum = checksum(headerByte: register, payload: payload)
        return [startByte, direction, register, UInt8(payload.count)]
            + payload
            + [UInt8(sum >> 8), UInt8(sum & 0x00FF), stopByte]
    }

    static func readRequest(_ register: Register) -> [UInt8] {
        frame(direction: readByte, register: register.rawValue, payload: [])
    }

    static func writeRequest(_ register: Register, payload: [UInt8]) -> [UInt8] {
        frame(direction: writeByte, register: register.rawValue, payload: payload)
    }

    /// The magic payload that unlocks factory mode.
    static var openFactoryMode: [UInt8] {
        writeRequest(.factoryModeOpen, payload: [0x56, 0x78])
    }

    /// Leaves factory mode without writing the EEPROM back.
    static var closeFactoryMode: [UInt8] {
        writeRequest(.factoryModeClose, payload: [0x00, 0x00])
    }

    /// Leaves factory mode *and commits the EEPROM*, which is the same thing as
    /// wiping the fault records the pack keeps behind register `0xAA`.
    ///
    /// It is the same register as `closeFactoryMode` — only the payload differs, so
    /// both answer on register `0x01` and nothing downstream can tell them apart by
    /// register alone. An otherwise empty factory bracket ending here is how the
    /// reference implementation clears the errors, and it is what the settings that
    /// have to survive a power cycle end with.
    static var saveAndCloseFactoryMode: [UInt8] {
        writeRequest(.factoryModeClose, payload: [0x28, 0x28])
    }

    // MARK: - Calibration

    /// The EEPROM registers a calibration writes to. Each takes one big-endian
    /// 16-bit word, and the pack works out its own correction from the true figure
    /// it is handed.
    enum Calibration {
        /// One register per cell, `0xB0` through `0xCF` — 32 of them. The word is
        /// the cell's true voltage in millivolts.
        static let cellBase: UInt8 = 0xB0
        static let cellCount = 32
        /// One register per NTC, `0xD0` through `0xD7`. The word is tenths of a
        /// kelvin, the same scale the readings come back in.
        static let temperatureBase: UInt8 = 0xD0
        static let temperatureCount = 8
        /// Zeroes the current reading; the word is always zero.
        static let idleCurrent: UInt8 = 0xAD
        /// Gain, one register per direction. The word is hundredths of an amp, the
        /// scale the current reading uses.
        static let chargeCurrent: UInt8 = 0xAE
        static let dischargeCurrent: UInt8 = 0xAF
    }

    private static func word(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0x00FF)]
    }

    private static func calibrationWrite(register: UInt8, word value: UInt16) -> [UInt8] {
        frame(direction: writeByte, register: register, payload: word(value))
    }

    /// Hands the pack the true voltage of one cell, in millivolts.
    static func calibrateCell(index: Int, millivolts: Int) -> [UInt8]? {
        guard (0..<Calibration.cellCount).contains(index),
              let value = UInt16(exactly: millivolts)
        else { return nil }
        return calibrationWrite(register: Calibration.cellBase + UInt8(index), word: value)
    }

    /// Hands the pack the true temperature at one sensor.
    static func calibrateTemperature(index: Int, celsius: Double) -> [UInt8]? {
        guard (0..<Calibration.temperatureCount).contains(index) else { return nil }
        let tenthsOfKelvin = ((celsius + 273.15) * 10).rounded()
        guard let value = UInt16(exactly: tenthsOfKelvin) else { return nil }
        return calibrationWrite(register: Calibration.temperatureBase + UInt8(index), word: value)
    }

    /// Tells the pack that what it is measuring right now is zero.
    static var calibrateIdleCurrent: [UInt8] {
        calibrationWrite(register: Calibration.idleCurrent, word: 0)
    }

    /// Hands the pack the true current flowing in the given direction, in amps.
    ///
    /// The magnitude is written whichever way the current runs: the register itself
    /// says which direction is being calibrated, and a negative word risks being read
    /// as a very large positive one by a firmware that treats it as unsigned.
    static func calibrateCurrent(charging: Bool, amperes: Double) -> [UInt8]? {
        let hundredths = (abs(amperes) * 100).rounded()
        guard let value = UInt16(exactly: hundredths), value <= UInt16(Int16.max) else { return nil }
        let register = charging ? Calibration.chargeCurrent : Calibration.dischargeCurrent
        return calibrationWrite(register: register, word: value)
    }

    // MARK: - MOSFETs

    /// Bit 0 switches the charge MOSFET *off*, bit 1 the discharge MOSFET *off*.
    static func mosControl(charge: Bool, discharge: Bool) -> [UInt8] {
        var code: UInt8 = 0
        if !charge { code |= 0b01 }
        if !discharge { code |= 0b10 }
        return writeRequest(.mosControl, payload: [0x00, code])
    }

    // MARK: - Hardware password

    /// The BMS wants each digit as its numeric value, not its ASCII code.
    private static func digits(_ password: String) -> [UInt8]? {
        guard password.count == 6 else { return nil }
        let values = password.compactMap { $0.wholeNumberValue }
        guard values.count == 6, values.allSatisfy({ (0...9).contains($0) }) else { return nil }
        return values.map(UInt8.init)
    }

    static func isValidPassword(_ password: String) -> Bool {
        digits(password) != nil
    }

    /// Unlocks the BMS. Must be sent before opening factory mode on a protected pack.
    static func enterPassword(_ password: String) -> [UInt8]? {
        guard let digits = digits(password) else { return nil }
        return writeRequest(.enterPassword, payload: [0x06] + digits)
    }

    /// Replaces a known password with a new one.
    static func changePassword(from current: String, to new: String) -> [UInt8]? {
        guard let current = digits(current), let new = digits(new) else { return nil }
        return writeRequest(.setPassword, payload: [0x0C] + current + new)
    }

    /// Sets a password on a pack that has none. The six leading bytes are the constant
    /// the firmware expects in place of a current password.
    static func createPassword(_ new: String) -> [UInt8]? {
        guard let new = digits(new) else { return nil }
        return writeRequest(.setPassword, payload: [0x0C, 0xD0, 0xD0, 0xD0, 0xD0, 0xCF, 0xCF] + new)
    }

    /// Clears the password. The payload is a fixed unlock sequence, sent after a
    /// successful `enterPassword`.
    static var clearPassword: [UInt8] {
        writeRequest(.clearPassword, payload: [0x06, 0x4A, 0x31, 0x42, 0x32, 0x44, 0x34])
    }

    // MARK: - Responses

    struct Response: Equatable {
        var register: UInt8
        var status: UInt8
        var payload: [UInt8]

        var isOK: Bool { status == 0x00 }
    }

    enum DecodingError: Error, Equatable {
        case tooShort
        case badFraming
        case lengthMismatch
        case badChecksum
    }

    /// Decodes one complete frame.
    ///
    /// The checksum is only enforced on successful frames: several firmwares answer
    /// a rejected write with a zeroed checksum, and dropping those would hide the
    /// error status the caller needs to see.
    static func decode(_ bytes: [UInt8]) throws -> Response {
        guard bytes.count >= overhead else { throw DecodingError.tooShort }
        guard bytes.first == startByte, bytes.last == stopByte else { throw DecodingError.badFraming }

        let length = Int(bytes[lengthIndex])
        guard bytes.count == overhead + length else { throw DecodingError.lengthMismatch }

        let payload = Array(bytes[4..<(4 + length)])
        let response = Response(register: bytes[1], status: bytes[2], payload: payload)

        if response.isOK {
            let expected = checksum(headerByte: bytes[2], payload: payload)
            let actual = UInt16(bytes[bytes.count - 3]) << 8 | UInt16(bytes[bytes.count - 2])
            guard expected == actual else { throw DecodingError.badChecksum }
        }
        return response
    }
}
