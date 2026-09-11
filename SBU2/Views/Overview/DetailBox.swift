//
//  DetailBox.swift
//  SBU2
//
//  The overview's headline box, in either of the two styles it can be drawn in.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// State of charge, power, current, voltage and capacity — the figures the overview
/// leads with.
///
/// Long-press to change how they are drawn. Both styles show exactly the same
/// numbers; only the dial in front of the state of charge comes and goes.
struct DetailBox: View {
    let info: BasicInfo
    let capacityUnit: CapacityUnit
    /// Full scale for the power meter. The same figure that calibrates the power dial
    /// on the GPS screen, so a pack only has to be told once what "a lot" means for it.
    let expectedPower: Int

    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        @Bindable var appSettings = appSettings

        Card {
            switch appSettings.overviewStyle {
            case .ring: ringLayout
            case .bars: barLayout
            }
        }
        .contextMenu {
            Picker("Info box style", selection: $appSettings.overviewStyle) {
                ForEach(OverviewStyle.allCases) { style in
                    Label(style.label, systemImage: style.symbol).tag(style)
                }
            }
        }
    }

    // MARK: - The dial

    private var ringLayout: some View {
        HStack(alignment: .center, spacing: 20) {
            RingGauge(fraction: chargeFraction,
                      tint: .stateOfChargeOverview(info.stateOfCharge)) {
                Text(info.stateOfChargeText)
                    .font(.system(size: 24, weight: .bold))
            }
            .frame(width: 140, height: 120)

            Divider()

            VStack(alignment: .leading, spacing: 13) {
                Text(info.powerText)
                    .font(.system(size: 19, weight: .bold))
                Text(info.currentText)
                    .font(.system(size: 14, weight: .bold))
                Text(info.voltageText)
                    .font(.system(size: 14, weight: .bold))
                Text(info.capacityText(unit: capacityUnit))
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - The bars

    private var barLayout: some View {
        VStack(alignment: .leading, spacing: 14) {
            meter(title: "State of charge",
                  value: info.stateOfChargeText,
                  fraction: chargeFraction,
                  tint: .stateOfChargeOverview(info.stateOfCharge),
                  anchor: .leading)

            // Out of the pack fills rightwards, the way any bar fills. Into it fills
            // back from the far end, so which way the energy is going can be read
            // without looking at the sign in front of the figure.
            meter(title: powerTitle,
                  value: info.powerText,
                  fraction: powerFraction,
                  tint: powerTint,
                  anchor: info.current > 0 ? .trailing : .leading)

            Divider()

            figure("Current", info.currentText)
            figure("Voltage", info.voltageText)
            figure("Capacity", info.capacityText(unit: capacityUnit))
        }
    }

    private func meter(title: String,
                       value: String,
                       fraction: Double,
                       tint: Color,
                       anchor: Alignment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(size: 19, weight: .bold))
                    .monospacedDigit()
            }
            LinearMeter(fraction: fraction, tint: tint, anchor: anchor, height: 14)
        }
    }

    private func figure(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    // MARK: - Figures behind the bars

    private var chargeFraction: Double { Double(info.stateOfCharge) / 100 }

    /// Against what this pack was told to treat as a full load. Nothing to measure
    /// against if that was never set, so the bar stays empty rather than inventing a
    /// scale.
    private var powerFraction: Double {
        guard expectedPower > 0 else { return 0 }
        return min(abs(info.power) / Double(expectedPower), 1)
    }

    /// The row says which way the current is going; the fill direction says it again.
    private var powerTitle: String {
        if info.current > 0 { return "Charging" }
        if info.current < 0 { return "Discharging" }
        return "Power"
    }

    private var powerTint: Color {
        if info.current > 0 { return .green }
        if info.current < 0 { return .orange }
        return .gray
    }
}
