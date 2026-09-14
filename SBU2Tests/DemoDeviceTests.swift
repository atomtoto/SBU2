//
//  DemoDeviceTests.swift
//  SBU2Tests
//

import Foundation
import Testing
@testable import SBU2

@Suite("Simulated pack")
struct DemoDeviceTests {

    @Test("A JBD pack reports what a JBD pack can measure, and nothing more")
    func imitatesJBD() {
        let demo = DemoDevice(family: .jbd)

        #expect(demo.cellVoltages.count == 4)
        #expect(demo.info.cellCount == demo.cellVoltages.count)
        // No JBD dongle measures the wire resistances, so the readout that shows them
        // must have nothing to offer here.
        #expect(demo.cellResistances.isEmpty)
        // It does say what model it is — one ordinary register, no factory mode — but
        // its serial number is in EEPROM behind that bracket, so it stays unread.
        #expect(demo.info.model != nil)
        #expect(demo.info.serialNumber == nil)
        // Nor does it keep a record of itself beyond its firmware version.
        #expect(demo.info.stateOfHealth == nil)
        #expect(demo.info.totalRuntime == nil)
        // Two probes, numbered, because the family has no names for them.
        #expect(demo.info.temperatures.count == 2)
        #expect(demo.info.temperatureLabels.isEmpty)
    }

    @Test("A JK pack reports everything a JK pack does")
    func imitatesJK() throws {
        let demo = DemoDevice(family: .jk)

        #expect(demo.cellVoltages.count == 16)
        #expect(demo.info.cellCount == demo.cellVoltages.count)
        #expect(demo.cellResistances.count == demo.cellVoltages.count)
        #expect((demo.cellResistances.min() ?? 0) > 0)

        #expect(demo.info.model != nil)
        #expect(demo.info.stateOfHealth != nil)
        #expect(demo.info.totalRuntime != nil)
        #expect(demo.info.serialNumber != nil)
        #expect(demo.info.hardwareVersion != nil)
        #expect(demo.info.powerOnCount != nil)

        // The third sensor is on the switches, which is why it is named rather than
        // numbered — and why it is the warmest of the three.
        #expect(demo.info.temperatures.count == 3)
        #expect(demo.info.temperatureLabel(2) == "MOS")
        let hottest = try #require(demo.info.temperatures.max())
        #expect(demo.info.temperatures[2] == hottest)
    }

    @Test("Each family reports the balancer the way that family reports it")
    func balancesInCharacter() throws {
        let jbd = DemoDevice(family: .jbd)
        let summary = try #require(CellSummary(voltages: jbd.cellVoltages))
        // The simulated string always sits far enough apart to be worth balancing;
        // without that neither branch would ever be seen.
        #expect(summary.deltaMillivolts > 5)

        // JBD names the cells it is shunting and says nothing else about it.
        #expect(jbd.info.balancingCells == [summary.highestIndex])
        #expect(jbd.info.balancerActive == false)
        #expect(jbd.info.balanceCurrent == nil)
        #expect(jbd.info.isBalancing)

        // JK names the two ends it is working between, and how much it is moving.
        let jk = DemoDevice(family: .jk)
        let jkSummary = try #require(CellSummary(voltages: jk.cellVoltages))
        #expect(jk.info.balancerActive)
        #expect(jk.info.balancingFrom == jkSummary.highestIndex)
        #expect(jk.info.balancingTo == jkSummary.lowestIndex)
        #expect((jk.info.balanceCurrent ?? 0) > 0)
    }

    @Test("The simulation keeps the pack coherent as it runs")
    func staysCoherent() {
        var demo = DemoDevice(family: .jk)
        for _ in 0..<200 { demo.step() }

        #expect(demo.info.stateOfCharge >= 0 && demo.info.stateOfCharge <= 100)
        #expect(demo.cellVoltages.count == 16)
        #expect(demo.cellResistances.count == 16)
        // The pack voltage is the string, not a figure of its own.
        let sum = demo.cellVoltages.reduce(0, +)
        #expect(abs(demo.info.packVoltage - sum) < 0.0001)
    }
}
