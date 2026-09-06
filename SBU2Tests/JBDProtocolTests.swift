//
//  JBDProtocolTests.swift
//  SBU2Tests
//

import Foundation
import Testing
@testable import SBU2

// A 4-cell LiFePO4 pack at 45 % SoC, discharging at 5 A, cell 2 balancing.
private let basicInfoFrame: [UInt8] = [
    0xDD, 0x03, 0x00, 0x1B,
    0x05, 0x2D, 0xFE, 0x0C, 0x11, 0xD0, 0x27, 0x10, 0x00, 0x0C, 0x2C, 0x3C,
    0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x20, 0x2D, 0x03, 0x04, 0x02,
    0x0B, 0xA6, 0x0B, 0x88,
    0xFB, 0x81, 0x77,
]

private let cellVoltageFrame: [UInt8] = [
    0xDD, 0x04, 0x00, 0x08,
    0x0C, 0xF8, 0x0C, 0xF3, 0x0C, 0xF6, 0x0C, 0xFA,
    0xFB, 0xED, 0x77,
]

@Suite("Request encoding")
struct RequestTests {

    @Test("Reading basic information")
    func basicInfoRequest() {
        #expect(JBD.readRequest(.basicInfo) == [0xDD, 0xA5, 0x03, 0x00, 0xFF, 0xFD, 0x77])
    }

    @Test("Reading cell voltages")
    func cellVoltageRequest() {
        #expect(JBD.readRequest(.cellVoltages) == [0xDD, 0xA5, 0x04, 0x00, 0xFF, 0xFC, 0x77])
    }

    @Test("Opening and closing factory mode")
    func factoryMode() {
        #expect(JBD.openFactoryMode == [0xDD, 0x5A, 0x00, 0x02, 0x56, 0x78, 0xFF, 0x30, 0x77])
        #expect(JBD.closeFactoryMode == [0xDD, 0x5A, 0x01, 0x02, 0x00, 0x00, 0xFF, 0xFD, 0x77])
    }

    @Test("MOSFET command: bit 0 disables charging, bit 1 disables discharging")
    func mosControl() {
        #expect(JBD.mosControl(charge: true, discharge: true)
                == [0xDD, 0x5A, 0xE1, 0x02, 0x00, 0x00, 0xFF, 0x1D, 0x77])
        #expect(JBD.mosControl(charge: false, discharge: true)
                == [0xDD, 0x5A, 0xE1, 0x02, 0x00, 0x01, 0xFF, 0x1C, 0x77])
        #expect(JBD.mosControl(charge: true, discharge: false)
                == [0xDD, 0x5A, 0xE1, 0x02, 0x00, 0x02, 0xFF, 0x1B, 0x77])
        #expect(JBD.mosControl(charge: false, discharge: false)
                == [0xDD, 0x5A, 0xE1, 0x02, 0x00, 0x03, 0xFF, 0x1A, 0x77])
    }
}

@Suite("Hardware password")
struct PasswordTests {

    @Test("Entering the password sends each digit as its numeric value")
    func enterPassword() {
        #expect(JBD.enterPassword("333333")
                == [0xDD, 0x5A, 0x06, 0x07, 0x06, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0xFF, 0xDB, 0x77])
    }

    @Test("Changing the password")
    func changePassword() {
        #expect(JBD.changePassword(from: "555555", to: "666666")
                == [0xDD, 0x5A, 0x07, 0x0D, 0x0C,
                    0x05, 0x05, 0x05, 0x05, 0x05, 0x05,
                    0x06, 0x06, 0x06, 0x06, 0x06, 0x06,
                    0xFF, 0x9E, 0x77])
    }

    @Test("Creating a password on a pack that has none")
    func createPassword() {
        #expect(JBD.createPassword("444444")
                == [0xDD, 0x5A, 0x07, 0x0D, 0x0C,
                    0xD0, 0xD0, 0xD0, 0xD0, 0xCF, 0xCF,
                    0x04, 0x04, 0x04, 0x04, 0x04, 0x04,
                    0xFA, 0xEA, 0x77])
    }

    @Test("Clearing the password")
    func clearPassword() {
        #expect(JBD.clearPassword
                == [0xDD, 0x5A, 0x09, 0x07, 0x06, 0x4A, 0x31, 0x42, 0x32, 0x44, 0x34, 0xFE, 0x83, 0x77])
    }

    @Test("Each digit becomes its numeric value, not its ASCII code")
    func digitsAreNumericValues() throws {
        let frame = try #require(JBD.enterPassword("102938"))
        #expect(Array(frame[4...10]) == [0x06, 1, 0, 2, 9, 3, 8])
    }

    @Test("A malformed password is refused before sending",
          arguments: ["12345", "1234567", "12345a", "", "  1234"])
    func rejectsMalformed(_ password: String) {
        #expect(!JBD.isValidPassword(password))
        #expect(JBD.enterPassword(password) == nil)
    }
}

@Suite("Cell summary")
struct CellSummaryTests {

    @Test("Extremes and delta")
    func extremes() throws {
        let summary = try #require(CellSummary(voltages: [3.320, 3.315, 3.318, 3.322]))
        #expect(summary.lowestIndex == 1)
        #expect(summary.highestIndex == 3)
        #expect(abs(summary.deltaMillivolts - 7) < 0.001)
    }

    @Test("Unpopulated cells are ignored")
    func ignoresUnpopulatedCells() throws {
        let summary = try #require(CellSummary(voltages: [3.320, 3.310, 0, 0]))
        #expect(summary.lowestIndex == 1)
        #expect(summary.highestIndex == 0)
    }

    @Test("No summary when no cell is live")
    func noLiveCells() {
        #expect(CellSummary(voltages: [0, 0]) == nil)
    }
}

@Suite("Response decoding")
struct ResponseTests {

    @Test("A valid frame")
    func validFrame() throws {
        let response = try JBD.decode(basicInfoFrame)
        #expect(response.register == 0x03)
        #expect(response.isOK)
        #expect(response.payload.count == 27)
    }

    @Test("A corrupted checksum")
    func corruptedChecksum() {
        var frame = basicInfoFrame
        frame[frame.count - 2] &+= 1
        #expect(throws: JBD.DecodingError.badChecksum) { try JBD.decode(frame) }
    }

    @Test("A length that does not match")
    func lengthMismatch() {
        var frame = basicInfoFrame
        frame[3] = 0x0A
        #expect(throws: JBD.DecodingError.lengthMismatch) { try JBD.decode(frame) }
    }

    @Test("Error frame: the firmware's zeroed checksum is not rejected")
    func errorFrame() throws {
        let response = try JBD.decode([0xDD, 0x00, 0x81, 0x00, 0x00, 0x00, 0x77])
        #expect(!response.isOK)
        #expect(response.status == 0x81)
    }
}

@Suite("BLE notification reassembly")
struct FrameAssemblerTests {

    @Test("A frame split into 20-byte packets")
    func splitFrame() {
        var assembler = FrameAssembler()
        #expect(assembler.append(Data(basicInfoFrame.prefix(20))).isEmpty)
        let frames = assembler.append(Data(basicInfoFrame.dropFirst(20)))
        #expect(frames == [basicInfoFrame])
    }

    @Test("Two frames in one notification")
    func coalescedFrames() {
        var assembler = FrameAssembler()
        let frames = assembler.append(Data(basicInfoFrame + cellVoltageFrame))
        #expect(frames == [basicInfoFrame, cellVoltageFrame])
    }

    @Test("Noise before the start byte is skipped")
    func resynchronisation() {
        var assembler = FrameAssembler()
        let frames = assembler.append(Data([0x11, 0x22] + cellVoltageFrame))
        #expect(frames == [cellVoltageFrame])
    }

    @Test("reset() empties the buffer")
    func resetClearsBuffer() {
        var assembler = FrameAssembler()
        _ = assembler.append(Data(basicInfoFrame.prefix(10)))
        assembler.reset()
        #expect(assembler.append(Data(cellVoltageFrame)) == [cellVoltageFrame])
    }
}

@Suite("Reading decoding")
struct BasicInfoTests {

    private func decoded() throws -> BasicInfo {
        let payload = try JBD.decode(basicInfoFrame).payload
        return try #require(BasicInfo.decode(payload: payload))
    }

    @Test("Electrical values")
    func electricalValues() throws {
        let info = try decoded()
        #expect(info.packVoltage == 13.25)
        #expect(info.current == -5.0)
        #expect(info.residualCapacity == 45.6)
        #expect(info.nominalCapacity == 100.0)
        #expect(info.stateOfCharge == 45)
        #expect(abs(info.power - (-66.25)) < 0.001)
    }

    @Test("Remaining time while discharging")
    func remainingTime() throws {
        let info = try decoded()
        let hours = try #require(info.remainingHours)
        #expect(abs(hours - 9.12) < 0.001)
    }

    @Test("Pack configuration and state")
    func packState() throws {
        let info = try decoded()
        #expect(info.cellCount == 4)
        #expect(info.cycles == 12)
        #expect(info.softwareVersion == "3.2")
        #expect(info.chargeMOSEnabled)
        #expect(info.dischargeMOSEnabled)
        #expect(info.protections.isEmpty)
        #expect(info.balancingCells == [1])
    }

    @Test("Temperatures converted to Celsius")
    func temperatures() throws {
        let info = try decoded()
        #expect(info.temperatures.count == 2)
        #expect(abs(info.temperatures[0] - 25.05) < 0.001)
        #expect(abs(info.temperatures[1] - 22.05) < 0.001)
    }

    @Test("Production date")
    func productionDate() throws {
        let info = try decoded()
        let date = try #require(info.productionDate)
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        #expect(components.year == 2022)
        #expect(components.month == 1)
        #expect(components.day == 28)
    }

    @Test("Protection flags are decoded bit by bit")
    func protectionFlags() throws {
        var payload = try JBD.decode(basicInfoFrame).payload
        // bit 2 = pack overvoltage, bit 10 = short circuit
        payload[16] = 0b0000_0100
        payload[17] = 0b0000_0100
        let info = try #require(BasicInfo.decode(payload: payload))
        #expect(info.protections == [.packOverVoltage, .shortCircuit])
    }

    @Test("A payload that is too short")
    func truncatedPayload() {
        #expect(BasicInfo.decode(payload: [0x05, 0x2D]) == nil)
    }
}

@Suite("Cell voltages")
struct CellVoltageTests {

    @Test("Conversion to volts")
    func decoding() throws {
        let payload = try JBD.decode(cellVoltageFrame).payload
        let voltages = CellVoltages.decode(payload: payload)
        #expect(voltages == [3.320, 3.315, 3.318, 3.322])
    }
}
