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

    /// "2 h 15 min" until full or empty, or `nil` when the current is too small to tell.
    var remainingTimeText: String? {
        guard let hours = remainingHours else { return nil }
        let total = Int((hours * 60).rounded())
        let (h, m) = (total / 60, total % 60)
        if h > 99 { return "> 99 h" }
        return h > 0 ? "\(h) h \(m) min" : "\(m) min"
    }
}

/// Per-cell figures derived from the voltage frame.
struct CellSummary {
    var lowestIndex: Int
    var highestIndex: Int
    var lowest: Double
    var highest: Double

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
    }
}
