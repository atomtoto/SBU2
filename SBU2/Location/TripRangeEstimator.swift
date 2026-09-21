//
//  TripRangeEstimator.swift
//  SBU2
//

import Foundation

/// Pure energy and range calculations kept separate from Core Location so their
/// units and fallbacks can be verified independently.
enum TripRangeEstimator {
    /// Remaining watt-hours based on nominal pack voltage.
    ///
    /// A measured pack voltage rises while charging and sags under load. Multiplying
    /// capacity by that moving value made the displayed range move even when neither
    /// the stored amp-hours nor the riding efficiency had changed. Cell count times
    /// nominal cell voltage is the stable conversion used elsewhere in the app.
    static func remainingEnergy(reading: BasicInfo,
                                cellNominalMillivolts: Int) -> Double {
        let configuredVoltage = Double(reading.cellCount * cellNominalMillivolts) / 1_000
        let nominalPackVoltage = configuredVoltage > 0 ? configuredVoltage : reading.packVoltage
        return max(0, reading.residualCapacity) * max(0, nominalPackVoltage)
    }

    static func distance(remainingEnergy: Double, efficiency: Double) -> Double? {
        guard remainingEnergy.isFinite, remainingEnergy >= 0,
              efficiency.isFinite, efficiency > 0 else { return nil }
        return remainingEnergy / efficiency
    }
}
