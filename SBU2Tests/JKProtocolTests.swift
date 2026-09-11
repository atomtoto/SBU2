//
//  JKProtocolTests.swift
//  SBU2Tests
//

import Foundation
import Testing
@testable import SBU2

/// Frames to decode.
private enum Fixtures {
    /// A real 24-cell frame, copied out of the reference implementation's own
    /// captured examples rather than made up here. 16 cells populated, resting at
    /// 84 %.
    static let cellInfo24: [UInt8] = [
        0x55, 0xAA, 0xEB, 0x90, 0x02, 0x8C, 0xFF, 0x0C, 0x01, 0x0D, 0x01, 0x0D,
        0xFF, 0x0C, 0x01, 0x0D, 0x01, 0x0D, 0xFF, 0x0C, 0x01, 0x0D, 0x01, 0x0D,
        0x01, 0x0D, 0x01, 0x0D, 0xFF, 0x0C, 0x01, 0x0D, 0x01, 0x0D, 0x01, 0x0D,
        0x01, 0x0D, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x0D,
        0x00, 0x00, 0x00, 0x00, 0x9D, 0x01, 0x96, 0x01, 0x8C, 0x01, 0x87, 0x01,
        0x84, 0x01, 0x84, 0x01, 0x83, 0x01, 0x84, 0x01, 0x85, 0x01, 0x81, 0x01,
        0x83, 0x01, 0x86, 0x01, 0x82, 0x01, 0x82, 0x01, 0x83, 0x01, 0x85, 0x01,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0xD0,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xBE, 0x00,
        0xBF, 0x00, 0xD2, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x54, 0x8E, 0x0B,
        0x01, 0x00, 0x68, 0x3C, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3D, 0x04,
        0x00, 0x00, 0x64, 0x00, 0x79, 0x04, 0xCA, 0x03, 0x10, 0x00, 0x01, 0x01,
        0xAA, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x07, 0x00, 0x01, 0x00, 0x00, 0x00, 0xD5, 0x02, 0x00, 0x00,
        0x00, 0x00, 0xAE, 0xD6, 0x3B, 0x40, 0x00, 0x00, 0x00, 0x00, 0x58, 0xAA,
        0xFD, 0xFF, 0x00, 0x00, 0x00, 0x01, 0x00, 0x02, 0x00, 0x00, 0xEC, 0xE6,
        0x4F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xCD
    ]

    /// A 32-cell frame built to order, because the reference carries no captured
    /// one. Every figure in it is placed at the 32-cell offsets and checked back out
    /// again by the tests, which is the whole point: the long layout's arithmetic —
    /// sixteen bytes of shift before the resistances and thirty-two after them — is
    /// the part most likely to be wrong.
    static let cellInfo32: [UInt8] = [
        0x55, 0xAA, 0xEB, 0x90, 0x02, 0x11, 0xE4, 0x0C, 0xE5, 0x0C, 0xE6, 0x0C,
        0xE7, 0x0C, 0xE8, 0x0C, 0xE9, 0x0C, 0xEA, 0x0C, 0xEB, 0x0C, 0xEC, 0x0C,
        0xED, 0x0C, 0xEE, 0x0C, 0xEF, 0x0C, 0xF0, 0x0C, 0xF1, 0x0C, 0xF2, 0x0C,
        0xF3, 0x0C, 0xF4, 0x0C, 0xF5, 0x0C, 0xF6, 0x0C, 0xF7, 0x0C, 0xF8, 0x0C,
        0xF9, 0x0C, 0xFA, 0x0C, 0xFB, 0x0C, 0xFC, 0x0C, 0xFD, 0x0C, 0xFE, 0x0C,
        0xFF, 0x0C, 0x00, 0x0D, 0x01, 0x0D, 0x02, 0x0D, 0x03, 0x0D, 0xFF, 0xFF,
        0xFF, 0xFF, 0xF3, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1C, 0x9C, 0x01, 0x00, 0x00, 0x00,
        0x00, 0x00, 0xCC, 0xCF, 0xFF, 0xFF, 0xD2, 0x00, 0xE1, 0x00, 0x20, 0x20,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x4D, 0x90, 0x59, 0x02, 0x00, 0x40, 0x0D,
        0x03, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x73
    ]
}

@Suite("JK requests")
struct JKRequestTests {

    @Test("A read request is twenty bytes, and the last one is the sum of the rest")
    func requestBytes() {
        let cellInfo = JK.request(.cellInfo)
        #expect(cellInfo.count == 20)
        // The request preamble is the answer's four bytes in a different order. Both
        // are deliberate, and swapping either breaks the pack's parser silently.
        #expect(Array(cellInfo.prefix(6)) == [0xAA, 0x55, 0x90, 0xEB, 0x96, 0x00])
        #expect(Array(cellInfo[6..<19]) == [UInt8](repeating: 0, count: 13))
        #expect(cellInfo[19] == 0x10)

        let deviceInfo = JK.request(.deviceInfo)
        #expect(Array(deviceInfo.prefix(5)) == [0xAA, 0x55, 0x90, 0xEB, 0x97])
        #expect(deviceInfo[19] == 0x11)
    }

    @Test("Switching a terminal is one register, four bytes wide, and its own sum")
    func switchFrames() {
        #expect(Array(JK.write(.chargingSwitch, on: true).prefix(7))
                == [0xAA, 0x55, 0x90, 0xEB, 0x1D, 0x04, 0x01])
        #expect(JK.write(.chargingSwitch, on: true)[19] == 0x9C)
        #expect(JK.write(.chargingSwitch, on: false)[19] == 0x9B)

        #expect(Array(JK.write(.dischargingSwitch, on: true).prefix(7))
                == [0xAA, 0x55, 0x90, 0xEB, 0x1E, 0x04, 0x01])
        #expect(JK.write(.dischargingSwitch, on: true)[19] == 0x9D)
        #expect(JK.write(.dischargingSwitch, on: false)[19] == 0x9C)

        // The two terminals are separate registers, unlike JBD's single one.
        #expect(JK.write(.chargingSwitch, on: true) != JK.write(.dischargingSwitch, on: true))
    }

    @Test("The checksum wraps rather than trapping")
    func checksumWraps() {
        #expect(JK.checksum([0xFF, 0x02]) == 0x01)
        #expect(JK.checksum([UInt8]()) == 0)
    }
}

@Suite("JK cell information")
struct JKCellInfoTests {

    @Test("The captured frame is intact and is recognised as the short layout")
    func recognisesTheShortLayout() {
        let frame = Fixtures.cellInfo24
        #expect(frame.count == 300)
        #expect(frame[4] == JK.FrameType.cellInfo.rawValue)
        #expect(JK.checksum(frame[0..<299]) == frame[299])
        #expect(JK.variant(ofCellInfo: frame) == .cells24)
    }

    @Test("Read the short frame the long way and nothing agrees, which is how it is told apart")
    func rejectsTheWrongLayout() {
        // The long layout looks for the pack's average sixteen bytes further on,
        // where this frame keeps a cell resistance. 0.388 V against a real 3.33 V.
        let frame = Fixtures.cellInfo24
        let asLong = JK.cellVoltages(frame, .cells32).filter { $0 > 0 }
        let mean = asLong.reduce(0, +) / Double(asLong.count)
        #expect(mean > 5.0)     // garbage, because it is reading past the cells
    }

    @Test("Every figure the overview needs comes back off the captured frame")
    func decodesTheShortFrame() throws {
        let info = try #require(JK.decodeCellInfo(Fixtures.cellInfo24, .cells24))

        #expect(abs(info.packVoltage - 53.251) < 0.001)
        #expect(info.current == 0)
        #expect(info.stateOfCharge == 84)
        #expect(abs(info.residualCapacity - 68.494) < 0.001)
        #expect(abs(info.nominalCapacity - 81.0) < 0.001)
        #expect(info.cycles == 0)
        #expect(info.chargeMOSEnabled)
        #expect(info.dischargeMOSEnabled)
        #expect(info.cellCount == 16)
        #expect(info.protections.isEmpty)

        // Two probes and the MOSFET sensor, in that order.
        #expect(info.temperatures.count == 3)
        #expect(abs(info.temperatures[0] - 19.0) < 0.01)
        #expect(abs(info.temperatures[1] - 19.1) < 0.01)
        #expect(abs(info.temperatures[2] - 21.0) < 0.01)

        // The pack is at rest, so the capacity and the state of charge should agree.
        #expect(abs(info.residualCapacity / info.nominalCapacity * 100 - 84) < 1)
    }

    @Test("Cell voltages come back in order, with the unpopulated ones left at zero")
    func decodesCellVoltages() {
        let voltages = JK.cellVoltages(Fixtures.cellInfo24, .cells24)
        #expect(voltages.count == 24)
        #expect(abs(voltages[0] - 3.327) < 0.0005)
        #expect(abs(voltages[1] - 3.329) < 0.0005)
        #expect(voltages[16] == 0)
        #expect(voltages[23] == 0)

        // The pack's own average, which is what the layout is recognised by.
        let live = voltages.filter { $0 > 0 }
        #expect(live.count == 16)
        #expect(abs(live.reduce(0, +) / 16 - 3.3285) < 0.0005)
    }

    @Test("The long layout shifts sixteen bytes before the resistances and thirty-two after")
    func decodesTheLongFrame() throws {
        let frame = Fixtures.cellInfo32
        #expect(JK.variant(ofCellInfo: frame) == .cells32)

        let info = try #require(JK.decodeCellInfo(frame, .cells32))
        #expect(abs(info.packVoltage - 105.5) < 0.001)
        #expect(abs(info.current + 12.34) < 0.001)      // negative: discharging
        #expect(info.stateOfCharge == 77)
        #expect(abs(info.residualCapacity - 154.0) < 0.001)
        #expect(abs(info.nominalCapacity - 200.0) < 0.001)
        #expect(info.cycles == 42)
        #expect(info.cellCount == 32)
        #expect(!info.chargeMOSEnabled)
        #expect(info.dischargeMOSEnabled)

        // The MOSFET sensor moves out of the way of the fault mask, which grew from
        // sixteen bits to thirty-two and took its old place.
        #expect(abs(info.temperatures[0] - 21.0) < 0.01)
        #expect(abs(info.temperatures[1] - 22.5) < 0.01)
        #expect(abs(info.temperatures[2] - 25.5) < 0.01)

        #expect(info.protections == [.dischargeOverCurrent, .packOverVoltage])

        let voltages = JK.cellVoltages(frame, .cells32)
        #expect(voltages.count == 32)
        #expect(abs(voltages[0] - 3.300) < 0.0005)
        #expect(abs(voltages[31] - 3.331) < 0.0005)
    }

    @Test("Fault bits map onto the protections that mean the same thing")
    func mapsFaults() {
        #expect(JK.protections(0) == [])
        #expect(JK.protections(1 << 5) == [.packOverVoltage])
        #expect(JK.protections(1 << 11) == [.cellUnderVoltage])
        // Both short-circuit bits say the same thing, so they collapse into one.
        #expect(JK.protections(1 << 7 | 1 << 14) == [.shortCircuit])

        // Bit 4 is "battery is fully charged", which is not a fault at all, and JK's
        // table has no cell-overvoltage bit anywhere in it. Nothing is invented to
        // fill the gap.
        #expect(JK.protections(1 << 4) == [])
        #expect(JK.protections(.max).contains(.cellOverVoltage) == false)
    }

    @Test("A frame shorter than the protocol allows decodes to nothing")
    func refusesShortFrames() {
        #expect(JK.decodeCellInfo(Array(Fixtures.cellInfo24.prefix(120)), .cells24) == nil)
        #expect(JK.variant(ofCellInfo: []) == nil)
    }
}

@Suite("JK device information")
struct JKDeviceInfoTests {

    /// The device-information example the reference carries, cut down to the fields
    /// this app reads: model, hardware version, software version, build date.
    private func deviceInfoFrame() -> [UInt8] {
        var frame = [UInt8](repeating: 0, count: 300)
        for (offset, byte) in JK.preamble.enumerated() { frame[offset] = byte }
        frame[4] = JK.FrameType.deviceInfo.rawValue
        for (offset, byte) in Array("JK_PB2A16S15P".utf8).enumerated() { frame[6 + offset] = byte }
        for (offset, byte) in Array("14.XA".utf8).enumerated() { frame[22 + offset] = byte }
        for (offset, byte) in Array("14.20".utf8).enumerated() { frame[30 + offset] = byte }
        for (offset, byte) in Array("231118".utf8).enumerated() { frame[78 + offset] = byte }
        frame[299] = JK.checksum(frame[0..<299])
        return frame
    }

    @Test("Model, versions and build date come back out")
    func decodes() throws {
        let identity = try #require(JK.decodeDeviceInfo(deviceInfoFrame()))
        #expect(identity.model == "JK_PB2A16S15P")
        #expect(identity.hardwareVersion == "14.XA")
        #expect(identity.softwareVersion == "14.20")

        let date = try #require(identity.productionDate)
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        #expect(components.year == 2023)
        #expect(components.month == 11)
        #expect(components.day == 18)
    }

    @Test("A pack that recorded no build date says so rather than inventing one")
    func noProductionDate() {
        #expect(JK.productionDate("") == nil)
        #expect(JK.productionDate("000000") == nil)
        #expect(JK.productionDate("23AB18") == nil)
    }
}

@Suite("JK reassembly")
struct JKFrameAssemblerTests {

    private let start = Date(timeIntervalSince1970: 1_000)

    /// The dongle hands over twenty bytes at a time, so a frame arrives in fifteen.
    private func notifications(_ frame: [UInt8]) -> [Data] {
        stride(from: 0, to: frame.count, by: 20).map { Data(frame[$0..<min($0 + 20, frame.count)]) }
    }

    @Test("Fifteen notifications make one frame, and not before the last of them")
    func assembles() {
        var assembler = JKFrameAssembler()
        let chunks = notifications(Fixtures.cellInfo24)
        #expect(chunks.count == 15)

        for chunk in chunks.dropLast() {
            #expect(assembler.append(chunk, at: start).isEmpty)
        }
        let frames = assembler.append(chunks[14], at: start)
        #expect(frames.count == 1)
        #expect(frames.first == Fixtures.cellInfo24)
    }

    @Test("Bytes before the preamble are skipped rather than shifting the frame")
    func resynchronises() {
        var assembler = JKFrameAssembler()
        // The tail of something that was already in flight when we subscribed.
        #expect(assembler.append(Data([0x01, 0x02, 0x03, 0x04, 0x05]), at: start).isEmpty)
        var frames: [[UInt8]] = []
        for chunk in notifications(Fixtures.cellInfo24) {
            frames += assembler.append(chunk, at: start)
        }
        #expect(frames.count == 1)
        #expect(frames.first == Fixtures.cellInfo24)
    }

    @Test("A frame whose sum does not add up is thrown away, not shown")
    func rejectsACorruptedFrame() {
        var corrupted = Fixtures.cellInfo24
        corrupted[150] = corrupted[150] &+ 1
        var assembler = JKFrameAssembler()
        var frames: [[UInt8]] = []
        for chunk in notifications(corrupted) {
            frames += assembler.append(chunk, at: start)
        }
        #expect(frames.isEmpty)
    }

    @Test("Two frames back to back both come out")
    func assemblesTwo() {
        var assembler = JKFrameAssembler()
        var frames: [[UInt8]] = []
        for chunk in notifications(Fixtures.cellInfo24) + notifications(Fixtures.cellInfo24) {
            frames += assembler.append(chunk, at: start)
        }
        #expect(frames.count == 2)
    }

    @Test("A half-received frame does not block the one after it forever")
    func dropsAStaleFrame() {
        var assembler = JKFrameAssembler()
        for chunk in notifications(Fixtures.cellInfo24).prefix(8) {
            _ = assembler.append(chunk, at: start)
        }
        // The rest never arrived. A later frame still gets through, because the
        // stalled one is given up on rather than left at the head of the buffer.
        var frames: [[UInt8]] = []
        let later = start.addingTimeInterval(JKFrameAssembler.staleAfter + 1)
        for chunk in notifications(Fixtures.cellInfo24) {
            frames += assembler.append(chunk, at: later)
        }
        #expect(frames.count == 1)
    }
}

@Suite("JK adapter")
struct JKAdapterTests {

    @Test("The terminals can be switched; the pack's settings still cannot")
    func writesOnlyTheTerminals() {
        let adapter = JKAdapter()
        #expect(adapter.supportsMOSControl)
        #expect(!adapter.supportsPasswordManagement)
        #expect(!adapter.supportsClearingAlerts)
        #expect(!adapter.supportsCalibration)
        #expect(adapter.clearAlertsCommands(password: nil).isEmpty)
        #expect(adapter.calibrationCommands(.idleCurrent, password: nil).isEmpty)
    }

    @Test("Only the terminal that was touched is written, and it expects no answer")
    func mosWrites() {
        // Writing both used to leave discharging broken: the two went out charge
        // first, and the pack took the first and dropped the second.
        let charging = JKAdapter().mosCommands(terminal: .charge,
                                               charge: true, discharge: false, password: nil)
        #expect(charging.map(\.bytes) == [JK.write(.chargingSwitch, on: true)])

        let discharging = JKAdapter().mosCommands(terminal: .discharge,
                                                  charge: true, discharge: false, password: nil)
        #expect(discharging.map(\.bytes) == [JK.write(.dischargingSwitch, on: false)])

        // The pack acknowledges nothing; the next streamed reading is the receipt.
        #expect(discharging.map(\.expectedRegister) == [nil])
        #expect(discharging.map(\.isPoll) == [false])
    }

    @Test("Switching one terminal never touches the other's register")
    func leavesTheOtherTerminalAlone() {
        let adapter = JKAdapter()
        for terminal in [MOSWriteTracker.Terminal.charge, .discharge] {
            let commands = adapter.mosCommands(terminal: terminal,
                                               charge: true, discharge: true, password: nil)
            #expect(commands.count == 1)
            let register = commands[0].bytes[4]
            #expect(register == (terminal == .charge
                                 ? JK.Register.chargingSwitch.rawValue
                                 : JK.Register.dischargingSwitch.rawValue))
        }
    }

    @Test("A password is not sent because the protocol has nowhere to put one")
    func noPasswordInTheWrite() {
        // Same bytes with a password as without. The reference writes these registers
        // with no authentication of any kind, and there is no unlock frame to send.
        let withPassword = JKAdapter().mosCommands(terminal: .charge,
                                                   charge: true, discharge: true, password: "1234")
        let without = JKAdapter().mosCommands(terminal: .charge,
                                              charge: true, discharge: true, password: nil)
        #expect(withPassword.map(\.bytes) == without.map(\.bytes))
        #expect(!JKAdapter().isValidPassword("1234"))
    }

    @Test("The pack is asked once and then left alone, because every command makes it beep")
    func stopsAskingOnceStreaming() {
        let adapter = JKAdapter()
        var clock = Date(timeIntervalSince1970: 1_000)
        adapter.now = { clock }

        let first = adapter.pollCommands()
        #expect(first.count == 2)
        #expect(first[0].expectedRegister == JK.FrameType.deviceInfo.rawValue)
        #expect(first[1].expectedRegister == JK.FrameType.cellInfo.rawValue)
        #expect(first.map(\.isPoll) == [true, true])

        // A second later, nothing has come back — but it was only just asked, so it
        // is not asked again. This is the difference between two beeps and a beep
        // every second.
        clock = clock.addingTimeInterval(1)
        #expect(adapter.pollCommands().isEmpty)

        // The pack answers and starts streaming, and keeps streaming. However long
        // that goes on, it is never asked for readings again — which is the one that
        // used to beep every second.
        for round in 0..<30 {
            for chunk in stride(from: 0, to: 300, by: 20).map({
                Data(Fixtures.cellInfo24[$0..<min($0 + 20, 300)])
            }) {
                _ = adapter.ingest(chunk)
            }
            // A second between readings, as a real pack streams.
            clock = clock.addingTimeInterval(1)
            let asked = adapter.pollCommands().map(\.expectedRegister)
            #expect(!asked.contains(JK.FrameType.cellInfo.rawValue),
                    "asked for readings again on round \(round)")
        }
    }

    @Test("A pack that will not say who it is stops being asked")
    func givesUpOnTheIdentity() {
        // Nothing here ever answers the device-info request. Asking forever would be
        // a beep every few seconds for the rest of the session, in exchange for a
        // version string.
        let adapter = JKAdapter()
        var clock = Date(timeIntervalSince1970: 1_000)
        adapter.now = { clock }

        var asks = 0
        for _ in 0..<20 {
            asks += adapter.pollCommands()
                .filter { $0.expectedRegister == JK.FrameType.deviceInfo.rawValue }.count
            clock = clock.addingTimeInterval(5)
        }
        #expect(asks == 3)
    }

    @Test("A stream that dries up is asked again")
    func asksAgainWhenTheStreamStops() {
        let adapter = JKAdapter()
        var clock = Date(timeIntervalSince1970: 1_000)
        adapter.now = { clock }
        _ = adapter.pollCommands()

        for chunk in stride(from: 0, to: 300, by: 20).map({
            Data(Fixtures.cellInfo24[$0..<min($0 + 20, 300)])
        }) {
            _ = adapter.ingest(chunk)
        }

        // Still talking a moment later: left alone.
        clock = clock.addingTimeInterval(2)
        #expect(adapter.pollCommands().isEmpty)

        // Gone quiet for longer than the pack is given: asked again.
        clock = clock.addingTimeInterval(10)
        let resumed = adapter.pollCommands().map(\.expectedRegister)
        #expect(resumed.contains(JK.FrameType.cellInfo.rawValue))

        // And not again straight afterwards, even though it is still quiet.
        clock = clock.addingTimeInterval(1)
        #expect(adapter.pollCommands().isEmpty)
    }

    @Test("A frame whose layout cannot be settled still produces a reading")
    func fallsBackRatherThanShowingNothing() {
        // A pack that reports no average of its own: neither layout can be confirmed
        // from the frame, and an empty screen would be the worst of the answers.
        var frame = Fixtures.cellInfo24
        frame[58] = 0
        frame[59] = 0
        frame[299] = JK.checksum(frame[0..<299])
        #expect(JK.variant(ofCellInfo: frame) == nil)

        let adapter = JKAdapter()
        var events: [BMSEvent] = []
        for chunk in stride(from: 0, to: 300, by: 20).map({
            Data(frame[$0..<min($0 + 20, 300)])
        }) {
            events += adapter.ingest(chunk)
        }
        #expect(events.count == 2)
        guard case .basicInfo(let info) = events.first?.kind else {
            Issue.record("Expected a reading even without a settled layout")
            return
        }
        #expect(info.stateOfCharge == 84)
    }

    @Test("A cell-info frame turns into a reading and a set of cell voltages")
    func ingestsAReading() {
        let adapter = JKAdapter()
        var events: [BMSEvent] = []
        for chunk in stride(from: 0, to: 300, by: 20).map({
            Data(Fixtures.cellInfo24[$0..<min($0 + 20, 300)])
        }) {
            events += adapter.ingest(chunk)
        }

        #expect(events.count == 2)
        guard case .basicInfo(let info) = events.first?.kind else {
            Issue.record("Expected a reading first")
            return
        }
        #expect(info.stateOfCharge == 84)
        #expect(info.cellCount == 16)

        guard case .cellVoltages(let voltages) = events.last?.kind else {
            Issue.record("Expected cell voltages second")
            return
        }
        #expect(voltages.filter { $0 > 0 }.count == 16)
    }
}
