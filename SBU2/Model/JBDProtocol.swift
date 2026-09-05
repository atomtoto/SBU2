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

        let length = Int(bytes[3])
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
