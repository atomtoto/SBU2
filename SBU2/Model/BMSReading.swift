//
//  BMSReading.swift
//  SBU2
//

import SwiftUI

/// One of the thirteen protection flags reported in the basic-information frame.
enum Protection: Int, CaseIterable, Identifiable {
    case cellOverVoltage = 0
    case cellUnderVoltage
    case packOverVoltage
    case packUnderVoltage
    case chargeOverTemperature
    case chargeUnderTemperature
    case dischargeOverTemperature
    case dischargeUnderTemperature
    case chargeOverCurrent
    case dischargeOverCurrent
    case shortCircuit
    case frontEndError
    case mosLockedIn

    var id: Int { rawValue }

    /// The wording SBU used in its overview.
    var label: String {
        switch self {
        case .cellOverVoltage: "Cell overvoltage"
        case .cellUnderVoltage: "Cell undervoltage"
        case .packOverVoltage: "Battery overvoltage"
        case .packUnderVoltage: "Battery undervoltage"
        case .chargeOverTemperature: "Temperature above charging limit"
        case .chargeUnderTemperature: "Temperature below charging limit"
        case .dischargeOverTemperature: "Temperature above discharging limit"
        case .dischargeUnderTemperature: "Temperature below discharging limit"
        case .chargeOverCurrent: "Charging overcurrent"
        case .dischargeOverCurrent: "Discharging overcurrent"
        case .shortCircuit: "Short circuit detected"
        case .frontEndError: "BMS error detected"
        case .mosLockedIn: "MOS locked"
        }
    }

    /// SBU drew a yellow triangle for most faults, a red octagon for the two that
    /// mean the pack cut out, and a blue info circle for the MOS lock.
    var symbol: String {
        switch self {
        case .shortCircuit, .frontEndError: "exclamationmark.octagon.fill"
        case .mosLockedIn: "info.circle"
        default: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .shortCircuit, .frontEndError: .red
        case .mosLockedIn: .blue
        default: .yellow
        }
    }
}

/// The values decoded from register `0x03`.
struct BasicInfo: Equatable {
    var packVoltage: Double = 0          // V
    var current: Double = 0              // A, positive while charging
    var residualCapacity: Double = 0     // Ah
    var nominalCapacity: Double = 0      // Ah
    var cycles: Int = 0
    var productionDate: Date?
    var balancingCells: Set<Int> = []
    var protections: Set<Protection> = []
    var softwareVersion: String = ""
    var stateOfCharge: Int = 0           // %
    var chargeMOSEnabled: Bool = false
    var dischargeMOSEnabled: Bool = false
    var cellCount: Int = 0
    var temperatures: [Double] = []      // °C

    var power: Double { packVoltage * current }

    /// Hours until full (while charging) or empty (while discharging).
    var remainingHours: Double? {
        guard abs(current) > 0.05 else { return nil }
        let capacity = current > 0 ? nominalCapacity - residualCapacity : residualCapacity
        guard capacity > 0 else { return nil }
        return capacity / abs(current)
    }

    /// Requires at least the fixed part of the frame: 23 bytes plus 2 per temperature sensor.
    static func decode(payload: [UInt8]) -> BasicInfo? {
        guard payload.count >= 23 else { return nil }

        var info = BasicInfo()
        info.packVoltage = Double(payload.uint16(at: 0)) / 100
        info.current = Double(payload.int16(at: 2)) / 100
        info.residualCapacity = Double(payload.uint16(at: 4)) / 100
        info.nominalCapacity = Double(payload.uint16(at: 6)) / 100
        info.cycles = Int(payload.uint16(at: 8))
        info.productionDate = Self.decodeProductionDate(payload.uint16(at: 10))

        // Cells 0…15 live in the first word, 16…31 in the second, LSB = lowest cell.
        let balanceBits = UInt32(payload.uint16(at: 14)) << 16 | UInt32(payload.uint16(at: 12))
        info.balancingCells = Set((0..<32).filter { balanceBits >> UInt32($0) & 1 == 1 })

        let protectionBits = payload.uint16(at: 16)
        info.protections = Set(Protection.allCases.filter { protectionBits >> UInt16($0.rawValue) & 1 == 1 })

        info.softwareVersion = String(format: "%.1f", Double(payload[18]) / 10)
        info.stateOfCharge = Int(payload[19])
        info.chargeMOSEnabled = payload[20] & 0b01 != 0
        info.dischargeMOSEnabled = payload[20] & 0b10 != 0
        info.cellCount = Int(payload[21])

        let sensorCount = Int(payload[22])
        var temperatures: [Double] = []
        for index in 0..<sensorCount {
            let offset = 23 + index * 2
            guard offset + 1 < payload.count else { break }
            // Reported in tenths of a Kelvin.
            temperatures.append(Double(payload.uint16(at: offset)) / 10 - 273.15)
        }
        info.temperatures = temperatures

        return info
    }

    /// Packed as `yyyyyyy mmmm ddddd` with the year counted from 2000.
    private static func decodeProductionDate(_ raw: UInt16) -> Date? {
        var components = DateComponents()
        components.day = Int(raw & 0x1F)
        components.month = Int(raw >> 5 & 0x0F)
        components.year = 2000 + Int(raw >> 9)
        guard components.day! > 0, components.month! > 0 else { return nil }
        return Calendar(identifier: .gregorian).date(from: components)
    }
}

/// The per-cell voltages decoded from register `0x04`, in volts.
enum CellVoltages {
    static func decode(payload: [UInt8]) -> [Double] {
        stride(from: 0, to: payload.count - 1, by: 2).map {
            Double(payload.uint16(at: $0)) / 1000
        }
    }
}

private extension Array where Element == UInt8 {
    func uint16(at index: Int) -> UInt16 {
        UInt16(self[index]) << 8 | UInt16(self[index + 1])
    }

    func int16(at index: Int) -> Int16 {
        Int16(bitPattern: uint16(at: index))
    }
}
