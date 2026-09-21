//
//  ChargeEstimatorTests.swift
//  SBU2Tests
//

import Foundation
import Testing
@testable import SBU2

@Suite("Remaining time")
struct ChargeEstimatorTests {

    private let start = Date(timeIntervalSince1970: 1_000)

    /// A 100 Ah pack holding `stored`, moving `current` amps — positive charging.
    private func reading(stored: Double, current: Double) -> BasicInfo {
        var info = BasicInfo()
        info.nominalCapacity = 100
        info.residualCapacity = stored
        info.current = current
        return info
    }

    /// Settles the average on a steady current, so the model can be read on its own
    /// without the smoothing still catching up.
    private func settled(_ info: BasicInfo, _ chemistry: CellChemistry) -> ChargeEstimator {
        var estimator = ChargeEstimator()
        for step in 0...120 {
            estimator.update(info, chemistry: chemistry, at: start.addingTimeInterval(Double(step)))
        }
        return estimator
    }

    @Test("Below the knee, the near stretch goes in at the current the pack is taking")
    func belowTheKnee() throws {
        // LFP at 50 %, 10 A. 45 Ah to the knee at 95 %, then 5 Ah at a third of the
        // rate: 4.5 h + 1.5 h.
        let hours = try #require(settled(reading(stored: 50, current: 10), .lithiumIronPhosphate).remainingHours)
        #expect(abs(hours - 6.0) < 0.05)
    }

    @Test("Past the knee it is all taper, whatever the chemistry says")
    func pastTheKnee() throws {
        // Li-ion at 90 %, past its 75 % knee. 10 Ah at a third of 10 A is 3 h — where
        // the old estimate said one, and the charge then took three.
        let hours = try #require(settled(reading(stored: 90, current: 10), .lithiumIon).remainingHours)
        #expect(abs(hours - 3.0) < 0.05)
    }

    @Test("The same pack at the same current answers differently for LFP and Li-ion")
    func chemistryChangesTheAnswer() throws {
        let info = reading(stored: 80, current: 10)
        // At 80 % the Li-ion pack is already tapering while the LFP one is not, so
        // the flatter chemistry finishes sooner even though both hold the same 20 Ah.
        let ion = try #require(settled(info, .lithiumIon).remainingHours)
        let iron = try #require(settled(info, .lithiumIronPhosphate).remainingHours)
        #expect(abs(ion - 6.0) < 0.05)      // 20 Ah, all of it tapered
        #expect(abs(iron - 3.0) < 0.05)     // 15 Ah at 10 A, then 5 Ah tapered
        #expect(iron < ion)
    }

    @Test("A spike in the current barely moves the answer")
    func averagingRidesOutASpike() throws {
        var estimator = settled(reading(stored: 50, current: 10), .lithiumIronPhosphate)
        let steady = try #require(estimator.remainingHours)

        // One reading at three times the current, as a compressor kicking in would
        // give. Dividing by the reading of the moment would have cut the estimate to
        // a third of itself on the spot.
        estimator.update(reading(stored: 50, current: 30),
                         chemistry: .lithiumIronPhosphate,
                         at: start.addingTimeInterval(121))
        let spiked = try #require(estimator.remainingHours)
        #expect(spiked > steady * 0.9)
    }

    @Test("A sustained change is followed, it is just not chased")
    func averagingFollowsARealChange() throws {
        var estimator = settled(reading(stored: 50, current: 10), .lithiumIronPhosphate)
        for step in 121...240 {
            estimator.update(reading(stored: 50, current: 20),
                             chemistry: .lithiumIronPhosphate,
                             at: start.addingTimeInterval(Double(step)))
        }
        // Two minutes of 20 A, against a half-minute window: the estimate should have
        // halved, give or take the tail of the average.
        let hours = try #require(estimator.remainingHours)
        #expect(abs(hours - 3.0) < 0.1)
    }

    @Test("Discharging is a straight division — nothing tapers on the way down")
    func discharging() throws {
        let hours = try #require(settled(reading(stored: 45.6, current: -5), .lithiumIon).remainingHours)
        #expect(abs(hours - 9.12) < 0.05)
    }

    @Test("A pack at rest, or already full, has no answer to give")
    func nothingToSay() {
        #expect(settled(reading(stored: 50, current: 0), .lithiumIon).remainingHours == nil)
        #expect(settled(reading(stored: 100, current: 10), .lithiumIon).remainingHours == nil)
    }

    @Test("Reversing direction starts the average again rather than averaging across")
    func reversalForgetsTheOldDirection() throws {
        var estimator = settled(reading(stored: 50, current: -10), .lithiumIronPhosphate)
        estimator.update(reading(stored: 50, current: 10),
                         chemistry: .lithiumIronPhosphate,
                         at: start.addingTimeInterval(121))
        // Straight onto the new current: 45 Ah at 10 A, then 5 Ah tapered. Carrying
        // the discharge into the average would have left it near zero, and the
        // estimate near infinity.
        let hours = try #require(estimator.remainingHours)
        #expect(abs(hours - 6.0) < 0.05)
    }

    @Test("Chemistry is guessed from the full-cell voltage when nobody has said")
    func inferredChemistry() {
        #expect(CellChemistry.inferred(fromCellFullVoltage: 3650) == .lithiumIronPhosphate)
        #expect(CellChemistry.inferred(fromCellFullVoltage: 4200) == .lithiumIon)

        var settings = DeviceSettings()
        settings.cellFullVoltage = 3650
        #expect(settings.chemistry == .lithiumIronPhosphate)
        settings.chemistry = .lithiumIon
        #expect(settings.chemistry == .lithiumIon)
    }

    @Test("An estimate an hour out is not printed to the minute")
    func roundsHonestly() {
        #expect((0.75).asRemainingTime == "45 min")
        // 2 h 17 min, rounded to the nearest five.
        #expect((2.29).asRemainingTime == "2 h 15 min")
        #expect((150.0).asRemainingTime == "> 99 h")
    }
}
