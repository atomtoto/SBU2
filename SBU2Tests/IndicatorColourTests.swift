//
//  IndicatorColourTests.swift
//  SBU2Tests
//

import SwiftUI
import Testing
@testable import SBU2

@Suite("Indicator colours")
struct IndicatorColourTests {

    @Test("The temperature light changes on the thresholds it is meant to")
    func packTemperature() {
        // Below freezing is its own kind of wrong rather than merely cold, so it
        // gets its own colour instead of sharing green with the happy range.
        #expect(Color.packTemperature(-0.1) == .blue)
        #expect(Color.packTemperature(0) == .green)
        #expect(Color.packTemperature(20) == .green)
        #expect(Color.packTemperature(34.9) == .green)
        #expect(Color.packTemperature(35) == .yellow)
        #expect(Color.packTemperature(44.9) == .yellow)
        // Approaching where a JBD pack's over-temperature protections usually sit.
        #expect(Color.packTemperature(45) == .red)
        #expect(Color.packTemperature(60) == .red)
    }

    @Test("The state-of-charge thresholds are unchanged by the new one")
    func stateOfCharge() {
        #expect(Color.stateOfChargeOverview(9) == .red)
        #expect(Color.stateOfChargeOverview(24) == .yellow)
        #expect(Color.stateOfChargeOverview(25) == .green)

        // The trip list has always used a higher second threshold than the overview.
        #expect(Color.stateOfChargeTrip(29) == .yellow)
        #expect(Color.stateOfChargeTrip(30) == .green)
    }

    @Test("A runtime is printed in the two largest units it has")
    func runtime() {
        #expect(TimeInterval(0).asRuntime == "0 h 0 min")
        #expect(TimeInterval(3_600 * 5 + 60 * 7).asRuntime == "5 h 7 min")
        #expect(TimeInterval(86_400 * 3 + 3_600 * 4).asRuntime == "3 d 4 h")
        // 1 y 129 d, which is what a pack running since 2023 reads.
        #expect(TimeInterval(86_400 * 494).asRuntime == "1 y 129 d")
        // Nothing runs for a negative length of time, but nothing crashes either.
        #expect(TimeInterval(-5).asRuntime == "0 h 0 min")
    }

    @Test("Every cell voltage style is labelled and none share a label")
    func cellVoltageStylesAreDistinct() {
        let labels = CellVoltageStyle.allCases.map(\.label)
        #expect(labels.count == 4)
        #expect(Set(labels).count == labels.count)
        #expect(CellVoltageStyle.allCases.map(\.symbol).contains("") == false)
    }
}
