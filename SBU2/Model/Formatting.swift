//
//  Formatting.swift
//  SBU2
//

import Foundation

extension Locale {
    /// The units the pack readings and trip figures are displayed in, following the
    /// measurement system of the current locale.
    var preferredTemperatureUnit: UnitTemperature {
        measurementSystem == .metric ? .celsius : .fahrenheit
    }

    var preferredDistanceUnit: UnitLength {
        measurementSystem == .metric ? .kilometers : .miles
    }

    var preferredSpeedUnit: UnitSpeed {
        measurementSystem == .metric ? .kilometersPerHour : .milesPerHour
    }
}

extension Double {
    func formatted(decimals: Int, unit: String) -> String {
        formatted(.number.precision(.fractionLength(decimals))) + " " + unit
    }
}

extension BasicInfo {

    var voltageText: String { packVoltage.formatted(decimals: 2, unit: "V") }

    var currentText: String { current.formatted(decimals: 2, unit: "A") }

    var powerText: String { power.formatted(decimals: 0, unit: "W") }

    var stateOfChargeText: String { "\(stateOfCharge) %" }

    /// What the pack says about its balancer.
    ///
    /// Where the two ends of the string are named — JK gives them outright — this
    /// reads as the direction charge is moving, which is the thing worth knowing: off
    /// the full cell and into the flat one. Otherwise it falls back to whichever of
    /// the two other things the family does say: how hard the balancer is working, or
    /// which cells it is working on.
    var balancingText: String {
        if let from = balancingFrom, let to = balancingTo {
            return "\(from + 1) → \(to + 1)"
        }
        if let balanceCurrent, abs(balanceCurrent) >= 0.001 {
            return abs(balanceCurrent).formatted(decimals: 3, unit: "A")
        }
        let numbered = balancingCells.sorted().map { String($0 + 1) }
        switch numbered.count {
        case 0: return "Balancing"
        case 1: return "Cell " + numbered[0]
        default: return "Cells " + numbered.joined(separator: ", ")
        }
    }

    /// The balancer's own current, where the pack reports one worth printing.
    var balanceCurrentText: String? {
        guard let balanceCurrent, abs(balanceCurrent) >= 0.001 else { return nil }
        return abs(balanceCurrent).formatted(decimals: 3, unit: "A")
    }

    /// What to put beside one temperature: the pack's own name for it where it has
    /// one, and its position in the list where it does not.
    func temperatureLabel(_ index: Int) -> String {
        index < temperatureLabels.count ? temperatureLabels[index] : String(index + 1)
    }

    func temperatureText(_ celsius: Double) -> String {
        let measurement = Measurement(value: celsius, unit: UnitTemperature.celsius)
            .converted(to: Locale.current.preferredTemperatureUnit)
        return measurement.value.formatted(.number.precision(.fractionLength(1)))
            + " " + Locale.current.preferredTemperatureUnit.symbol
    }

    /// Remaining capacity, either as amp-hours or as an energy estimate.
    ///
    /// The watt-hour figure multiplies the amp-hours by the *measured* pack voltage,
    /// which is the honest conversion. SBU instead multiplied by the configured cell
    /// nominal voltage times a hardcoded 13 cells, which was wrong for any other pack.
    func capacityText(unit: CapacityUnit) -> String {
        switch unit {
        case .ampereHours:
            return residualCapacity.formatted(decimals: 2, unit: "Ah")
                + " / " + nominalCapacity.formatted(decimals: 2, unit: "Ah")
        case .wattHours:
            let reference = packVoltage > 0 ? packVoltage : 0
            return (residualCapacity * reference / 1000).formatted(decimals: 2, unit: "kWh")
                + " / " + (nominalCapacity * reference / 1000).formatted(decimals: 2, unit: "kWh")
        }
    }

}

extension TimeInterval {
    /// A span of years and days, or days and hours, or hours and minutes.
    ///
    /// A pack that has been running for over a year does not need the seconds it has
    /// been running for, and the two largest units it has are always the two worth
    /// printing.
    var asRuntime: String {
        let total = Int(max(self, 0))
        let (days, hours) = (total / 86_400, total % 86_400 / 3_600)
        if days >= 365 {
            let (years, remainder) = (days / 365, days % 365)
            return "\(years) y \(remainder) d"
        }
        if days > 0 { return "\(days) d \(hours) h" }
        return "\(hours) h \(total % 3_600 / 60) min"
    }
}

extension Double {
    /// This many hours as "2 h 15 min", or "45 min" under the hour.
    ///
    /// Rounded to five minutes once there is an hour or more of it left. An estimate
    /// that far out is not good to the minute, and printing it to the minute only
    /// invites the reader to believe that it is.
    var asRemainingTime: String {
        let step = self >= 1 ? 5.0 : 1.0
        let total = Int((self * 60 / step).rounded() * step)
        let (hours, minutes) = (total / 60, total % 60)
        if hours > 99 { return "> 99 h" }
        return hours > 0 ? "\(hours) h \(minutes) min" : "\(minutes) min"
    }
}

/// Per-cell figures derived from the voltage frame.
struct CellSummary {
    var lowestIndex: Int
    var highestIndex: Int
    var lowest: Double
    var highest: Double
    /// The mean of the populated cells, which is the pack's own voltage divided by
    /// its cell count — and a fair bit steadier than either extreme.
    var average: Double

    var deltaMillivolts: Double { (highest - lowest) * 1000 }

    init?(voltages: [Double]) {
        let live = voltages.enumerated().filter { $0.element > 0 }
        guard let low = live.min(by: { $0.element < $1.element }),
              let high = live.max(by: { $0.element < $1.element })
        else { return nil }
        lowestIndex = low.offset
        highestIndex = high.offset
        lowest = low.element
        highest = high.element
        average = live.reduce(0) { $0 + $1.element } / Double(live.count)
    }
}
