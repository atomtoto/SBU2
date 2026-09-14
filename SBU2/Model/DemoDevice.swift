//
//  DemoDevice.swift
//  SBU2
//

import Foundation

/// Generates plausible readings for a LiFePO4 pack so the whole interface can be used
/// without a BMS in range — the simulator has no Bluetooth at all.
///
/// It simulates one family at a time. The two the app speaks do not report the same
/// things — a JK pack measures the resistance of every cell wire, names the sensor on
/// its MOSFETs, says which two cells the balancer is working between and keeps a
/// record of itself; a JBD one does none of that, and in exchange accepts the
/// calibrations and the hardware password that JK has nowhere to put. Picking the
/// family in the demo device's settings is therefore the only way to see, without the
/// hardware, what each of them actually offers.
struct DemoDevice {

    static let identifier = "demo"

    /// The family this pack is pretending to be.
    let family: BMSProtocolID

    private(set) var info = BasicInfo()
    private(set) var cellVoltages: [Double] = []
    /// Only a JK pack measures these, so on a JBD one the readout is not offered at
    /// all — which is the point of being able to switch.
    private(set) var cellResistances: [Double] = []

    private var charge: Double = 0.55        // 0…1
    private var charging = true
    private var tick = 0

    /// A JBD dongle is usually on a small pack and a JK on a big one, and the
    /// difference is worth seeing: sixteen cells is where the compact voltage styles
    /// start to earn their place.
    private var cellCount: Int { family == .jk ? 16 : 4 }

    init(family: BMSProtocolID = .jbd) {
        self.family = family
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
        cellVoltages = (0..<cellCount).map { index in
            restVoltage + sag + sin(Double(index) * 1.7) * 0.004
                + sin(Double(tick) / 9) * 0.001
        }

        var reading = BasicInfo()
        reading.packVoltage = cellVoltages.reduce(0, +)
        reading.current = current + sin(Double(tick) / 5) * 0.4
        reading.nominalCapacity = nominal
        reading.residualCapacity = nominal * charge
        reading.stateOfCharge = Int((charge * 100).rounded())
        reading.cellCount = cellVoltages.count
        reading.cycles = 42
        reading.productionDate = DateComponents(calendar: .init(identifier: .gregorian),
                                                year: 2022, month: 1, day: 28).date
        reading.chargeMOSEnabled = info.chargeMOSEnabled
        reading.dischargeMOSEnabled = info.dischargeMOSEnabled
        reading.temperatures = [21.5 + sin(Double(tick) / 20) * 1.5,
                                23.0 + cos(Double(tick) / 25) * 1.0]

        switch family {
        case .jbd:
            reading.softwareVersion = "3.2"
            cellResistances = []
        case .jk:
            reading.softwareVersion = "11.26"
            reading.hardwareVersion = "11.0"
            reading.serialNumber = "SBU2DEMO0001"
            reading.powerOnCount = 37
            reading.stateOfHealth = 98
            reading.totalRuntime = 420 * 24 * 3600 + 7 * 3600
            // The third sensor is on the switches rather than in the cells, and runs
            // warmer than either probe — which is what the thermometers have to stay
            // readable through.
            reading.temperatures.append(29.0 + sin(Double(tick) / 15) * 2.0)
            reading.temperatureLabels = ["1", "2", "MOS"]
            cellResistances = (0..<cellCount).map { 0.385 + Double($0 % 5) * 0.007 }
        }

        applyBalancing(to: &reading)
        info = reading
    }

    /// Balances the string once it has drifted far enough apart, the way the family
    /// being simulated would report it: JBD names the cells it is shunting, JK names
    /// the state of the balancer, the current it is moving and the two cells it is
    /// moving it between.
    private func applyBalancing(to reading: inout BasicInfo) {
        guard let summary = CellSummary(voltages: cellVoltages),
              summary.deltaMillivolts > 5 else { return }

        switch family {
        case .jbd:
            reading.balancingCells = [summary.highestIndex]
        case .jk:
            reading.balancerActive = true
            reading.balanceCurrent = 0.42
            reading.balancingFrom = summary.highestIndex
            reading.balancingTo = summary.lowestIndex
            reading.balancingCells = [summary.highestIndex, summary.lowestIndex]
        }
    }

    /// The demo pack accepts MOSFET commands immediately — there is no BMS to answer.
    mutating func setMOS(charge: Bool, discharge: Bool) {
        info.chargeMOSEnabled = charge
        info.dischargeMOSEnabled = discharge
    }
}
