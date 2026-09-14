//
//  ChargeEstimator.swift
//  SBU2
//

import Foundation

/// How long until the pack is full, or empty.
///
/// What this replaces was the amp-hours still missing divided by the current of the
/// moment, which is wrong in two separate ways.
///
/// The current of the moment jumps about — a couple of amps either way between one
/// reading and the next — and dividing by it made the answer jump with it, from two
/// hours to forty minutes and back inside a few seconds. So the current is averaged
/// first, over about half a minute.
///
/// And a lithium charger does not hold the current steady to the end. It holds it
/// while it can, then reaches the voltage it was aiming for and holds *that*
/// instead, letting the current fall away as the pack fills. Everything after that
/// knee arrives far more slowly than a plain division assumes, which is why the last
/// stretch of a charge always outlasted what the app promised. Where the knee sits
/// is the one thing that really separates the two chemistries.
struct ChargeEstimator {

    /// Below this the pack is resting, or as near as makes no difference, and there
    /// is nothing to extrapolate from.
    private static let minimumCurrent = 0.05

    /// Roughly how long the average looks back. Long enough to sit still through the
    /// ripple of a real load, short enough to follow a charger that actually changes
    /// its mind.
    private static let averagingWindow: TimeInterval = 30

    /// What the pack accepts past the knee, as a fraction of what it was accepting
    /// when it got there.
    ///
    /// The current decays roughly exponentially from the knee down to the trickle
    /// the charger gives up at — a twentieth of it, give or take. Averaged over that
    /// decay the figure is `(1 - k) / ln(1/k)` of the starting current, which for a
    /// cut-off anywhere between a fiftieth and a tenth lands between a quarter and
    /// two fifths. A third sits in the middle. The same ratio holds partway down the
    /// curve as at the top — an exponential looks the same wherever it is cut — so
    /// this works whether the knee is still ahead or already behind.
    private static let taperedRate = 1.0 / 3.0

    private var averagedCurrent: Double?
    private var lastReading: Date?
    private var reading: BasicInfo?
    private var chemistry: CellChemistry = .lithiumIon

    /// Feeds in one set of readings. `now` is injectable so the averaging can be
    /// tested without waiting for it.
    mutating func update(_ info: BasicInfo, chemistry: CellChemistry, at now: Date = .now) {
        self.chemistry = chemistry
        reading = info

        // A pack at rest is not a slow charge, and letting it into the average would
        // drag a real current down for half a minute after one starts.
        guard abs(info.current) > Self.minimumCurrent else {
            forget()
            return
        }
        // A reversal is a different question, not a continuation of this one.
        if let averagedCurrent, averagedCurrent.sign != info.current.sign {
            forget()
        }
        averagedCurrent = averaging(info.current, at: now)
        lastReading = now
    }

    /// Drops the history. Call it when the link goes, so a charge measured before a
    /// reconnection cannot flavour the one after it.
    mutating func forget() {
        averagedCurrent = nil
        lastReading = nil
    }

    /// Hours until full while charging, until empty while discharging, and `nil`
    /// when the pack is resting or the answer would be meaningless.
    var remainingHours: Double? {
        guard let reading, let current = averagedCurrent,
              abs(current) > Self.minimumCurrent
        else { return nil }
        return current > 0 ? hoursToFull(reading, current) : hoursToEmpty(reading, -current)
    }

    /// Two stretches at two different rates: whatever is left before the knee goes in
    /// at the current the pack is taking now, and whatever is left after it goes in
    /// at a third of that.
    private func hoursToFull(_ info: BasicInfo, _ current: Double) -> Double? {
        guard info.nominalCapacity > 0 else { return nil }
        let stored = min(max(info.residualCapacity, 0), info.nominalCapacity)
        let missing = info.nominalCapacity - stored
        guard missing > 0 else { return nil }

        let knee = chemistry.constantVoltageOnset * info.nominalCapacity
        // Nothing if the knee is already behind, in which case it is all tapered.
        let atFullRate = min(max(knee - stored, 0), missing)
        let tapered = missing - atFullRate

        return atFullRate / current + tapered / (current * Self.taperedRate)
    }

    /// Nothing tapers on the way down: a pack under a steady load empties at a steady
    /// rate, and the load is what the averaging is for.
    private func hoursToEmpty(_ info: BasicInfo, _ current: Double) -> Double? {
        guard info.residualCapacity > 0 else { return nil }
        return info.residualCapacity / current
    }

    private func averaging(_ current: Double, at now: Date) -> Double {
        guard let previous = averagedCurrent, let lastReading else { return current }
        let elapsed = now.timeIntervalSince(lastReading)
        guard elapsed > 0 else { return previous }
        // Weighted by how long it has been rather than by how many readings have
        // arrived, so a link limping along at one reading every few seconds settles
        // at the same speed as a healthy one.
        let weight = 1 - exp(-elapsed / Self.averagingWindow)
        return previous + weight * (current - previous)
    }
}
