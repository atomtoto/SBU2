//
//  DemoDevice.swift
//  SBU2
//

import Foundation

/// Generates plausible readings for a 4-cell LiFePO4 pack so the whole interface can
/// be used without a BMS in range — the simulator has no Bluetooth at all.
struct DemoDevice {

    static let identifier = "demo"

    private(set) var info = BasicInfo()
    private(set) var cellVoltages: [Double] = []

    private var charge: Double = 0.55        // 0…1
    private var charging = true
    private var tick = 0

    init() {
        info.chargeMOSEnabled = true
        info.dischargeMOSEnabled = true
        step()
    }

    /// Advances the simulation by one polling interval.
    mutating func step() {
        tick += 1

        let current: Double = charging ? 12.5 : -8.4
        charge += current / 100 / 3600 * 30   // 30x real time, so the ring visibly moves
        if charge >= 0.98 { charging = false }
        if charge <= 0.15 { charging = true }

        let nominal = 100.0
        // Cells drift apart slightly, and the pack sags under load.
        let restVoltage = 3.20 + charge * 0.15
        let sag = current * 0.002
        let spread = [0.0, 0.004, -0.003, 0.002]
        cellVoltages = spread.map { restVoltage + sag + $0 + sin(Double(tick) / 9) * 0.001 }

        var reading = BasicInfo()
        reading.packVoltage = cellVoltages.reduce(0, +)
        reading.current = current + sin(Double(tick) / 5) * 0.4
        reading.nominalCapacity = nominal
        reading.residualCapacity = nominal * charge
        reading.stateOfCharge = Int((charge * 100).rounded())
        reading.cellCount = cellVoltages.count
        reading.cycles = 42
        reading.softwareVersion = "3.2"
        reading.productionDate = DateComponents(calendar: .init(identifier: .gregorian),
                                                year: 2022, month: 1, day: 28).date
        reading.chargeMOSEnabled = info.chargeMOSEnabled
        reading.dischargeMOSEnabled = info.dischargeMOSEnabled
        reading.temperatures = [21.5 + sin(Double(tick) / 20) * 1.5,
                                23.0 + cos(Double(tick) / 25) * 1.0]
        // Balance the highest cell whenever the spread is wide enough, as a real BMS would.
        if let summary = CellSummary(voltages: cellVoltages), summary.deltaMillivolts > 5 {
            reading.balancingCells = [summary.highestIndex]
        }
        info = reading
    }

    /// The demo pack accepts MOSFET commands immediately — there is no BMS to answer.
    mutating func setMOS(charge: Bool, discharge: Bool) {
        info.chargeMOSEnabled = charge
        info.dischargeMOSEnabled = discharge
    }
}
