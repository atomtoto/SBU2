//
//  TripRangeEstimatorTests.swift
//  SBU2Tests
//

import Testing
@testable import SBU2

@Suite("Remaining range")
struct TripRangeEstimatorTests {
    @Test("Nominal voltage keeps stored energy stable under pack-voltage sag")
    func nominalVoltageIsStable() {
        var reading = BasicInfo()
        reading.cellCount = 16
        reading.residualCapacity = 50
        reading.packVoltage = 58

        let first = TripRangeEstimator.remainingEnergy(reading: reading,
                                                       cellNominalMillivolts: 3_200)
        reading.packVoltage = 48
        let sagged = TripRangeEstimator.remainingEnergy(reading: reading,
                                                        cellNominalMillivolts: 3_200)

        #expect(first == 2_560)
        #expect(sagged == first)
    }

    @Test("Measured pack voltage remains a safe fallback without cell metadata")
    func measuredVoltageFallback() {
        var reading = BasicInfo()
        reading.residualCapacity = 10
        reading.packVoltage = 52

        #expect(TripRangeEstimator.remainingEnergy(reading: reading,
                                                   cellNominalMillivolts: 3_700) == 520)
    }

    @Test("Watt-hours per distance convert directly to remaining distance")
    func rangeUnits() throws {
        let distance = try #require(TripRangeEstimator.distance(remainingEnergy: 2_560,
                                                                efficiency: 20))
        #expect(distance == 128)
        #expect(TripRangeEstimator.distance(remainingEnergy: 2_560, efficiency: 0) == nil)
    }
}
