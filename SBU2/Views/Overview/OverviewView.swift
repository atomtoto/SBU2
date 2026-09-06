//
//  OverviewView.swift
//  SBU2
//
//  Reproduces SBU's Overview_v2 box for box.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct OverviewView: View {
    @Environment(BMSConnection.self) private var connection
    @Environment(AppSettings.self) private var appSettings

    @State private var pendingMOS: MOSChange?

    var body: some View {
        @Bindable var connection = connection

        ScrollView {
            LazyVStack(spacing: 10) {
                if connection.settings.liontronMode == .autoEnabled {
                    LiontronModeWarning()
                }
                DetailBox(info: connection.info, capacityUnit: appSettings.capacityUnit)
                    .padding(.top, 5)
                ButtonBox(info: connection.info,
                          settings: connection.settings,
                          enabled: connection.canControlMOS && !connection.isWritingMOS) { change in
                    pendingMOS = change
                }
                if showChargeBox {
                    ChargeBox(settings: $connection.settings)
                }
                CellTemperatureBox(info: connection.info,
                                   summary: connection.cellSummary)
                if !connection.cellVoltages.isEmpty {
                    CellVoltageBox(voltages: connection.cellVoltages,
                                   balancing: connection.info.balancingCells,
                                   summary: connection.cellSummary,
                                   emptyMillivolts: Double(connection.settings.cellEmptyVoltage),
                                   fullMillivolts: Double(connection.settings.cellFullVoltage))
                }
                BatteryInfoBox(info: connection.info)
                if let error = connection.lastError {
                    Card {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                            Text(error)
                            Spacer(minLength: 0)
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
        }
        .confirmationDialog(pendingMOS?.question ?? "",
                            isPresented: Binding(get: { pendingMOS != nil },
                                                 set: { if !$0 { pendingMOS = nil } }),
                            titleVisibility: .visible) {
            if let change = pendingMOS {
                Button(change.confirmTitle,
                       role: change.isDisabling ? ButtonRole.destructive : nil) {
                    connection.setMOS(charge: change.charge, discharge: change.discharge)
                    pendingMOS = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingMOS = nil }
        } message: {
            Text("This command is written to the BMS and really cuts the current on that terminal.")
        }
    }

    /// SBU showed the charge box whenever current was flowing in, or when the user
    /// asked to always see it — the first case does not test `chargeLimitEnabled`.
    private var showChargeBox: Bool {
        Int(connection.info.current) > 0
            || (connection.settings.alwaysShowChargeLimit && connection.settings.chargeLimitEnabled)
    }
}

/// A requested MOSFET state, held until the user confirms it.
struct MOSChange: Equatable {
    var charge: Bool
    var discharge: Bool
    var isDisabling: Bool
    var question: String
    var confirmTitle: String
}

// MARK: - Liontron warning

private struct LiontronModeWarning: View {
    @State private var collapsed = true

    var body: some View {
        VStack {
            Button {
                collapsed.toggle()
            } label: {
                HStack(alignment: .center, spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .renderingMode(.original)
                    Text("Liontron protection mode active!")
                    Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 25, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .buttonStyle(PlainButtonStyle())

            VStack {
                Text("You might need to enter the hardware password in settings")
                    .multilineTextAlignment(.center)
                    .animation(.none, value: collapsed)
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: collapsed ? 0 : .none)
            .clipped()
            .animation(.easeOut, value: collapsed)
            .padding(collapsed ? 0 : 8)
            .background {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
    }
}

// MARK: - Detail box

private struct DetailBox: View {
    let info: BasicInfo
    let capacityUnit: CapacityUnit

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 20) {
                RingGauge(fraction: Double(info.stateOfCharge) / 100,
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
    }
}

// MARK: - Charge / discharge buttons

private struct ButtonBox: View {
    let info: BasicInfo
    let settings: DeviceSettings
    let enabled: Bool
    let onChange: (MOSChange) -> Void

    private static let on = Color(red: 0, green: 0.6, blue: 0.1)
    private static let off = Color(red: 0.8, green: 0.3, blue: 0.05)

    /// Blue with a clock badge when the charge is being held back on purpose.
    private var chargeHeldForLater: Bool {
        settings.chargeLimitEnabled && settings.refillLaterEnabled && !info.chargeMOSEnabled
    }

    private var chargeColor: Color {
        if chargeHeldForLater { return .blue }
        guard settings.liontronMode != .autoEnabled else { return .gray }
        return info.chargeMOSEnabled ? Self.on : Self.off
    }

    private var chargeSymbol: String {
        if chargeHeldForLater { return "bolt.badge.clock.fill" }
        guard settings.liontronMode != .autoEnabled else { return "bolt.slash.fill" }
        return info.chargeMOSEnabled ? "bolt.fill" : "bolt.slash.fill"
    }

    private var dischargeColor: Color {
        guard settings.liontronMode != .autoEnabled else { return .gray }
        return info.dischargeMOSEnabled ? Self.on : Self.off
    }

    private var dischargeSymbol: String {
        guard settings.liontronMode != .autoEnabled else { return "bolt.slash.fill" }
        return info.dischargeMOSEnabled ? "bolt.fill" : "bolt.slash.fill"
    }

    var body: some View {
        Card(padding: 0) {
            HStack(alignment: .center, spacing: 20) {
                MOSButton(title: "Charging", color: chargeColor, symbol: chargeSymbol) {
                    onChange(MOSChange(charge: !info.chargeMOSEnabled,
                                       discharge: info.dischargeMOSEnabled,
                                       isDisabling: info.chargeMOSEnabled,
                                       question: info.chargeMOSEnabled ? "Disable charging?" : "Enable charging?",
                                       confirmTitle: info.chargeMOSEnabled ? "Disable charging" : "Enable charging"))
                }
                MOSButton(title: "Discharging", color: dischargeColor, symbol: dischargeSymbol) {
                    onChange(MOSChange(charge: info.chargeMOSEnabled,
                                       discharge: !info.dischargeMOSEnabled,
                                       isDisabling: info.dischargeMOSEnabled,
                                       question: info.dischargeMOSEnabled ? "Disable discharging?" : "Enable discharging?",
                                       confirmTitle: info.dischargeMOSEnabled ? "Disable discharging" : "Enable discharging"))
                }
            }
            .padding(.vertical, 10)
            .animation(.easeInOut(duration: 0.25), value: chargeColor)
            .animation(.easeInOut(duration: 0.25), value: dischargeColor)
        }
        .disabled(!enabled)
    }
}

private struct MOSButton: View {
    let title: String
    let color: Color
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            action()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(color)
                    .frame(width: 140, height: 35)
                HStack {
                    Text(title)
                        .font(.system(size: 16))
                    Image(systemName: symbol)
                }
                .foregroundColor(.white)
            }
        }
        .accessibilityLabel(title)
    }
}

// MARK: - Temperatures and cell extremes

private struct CellTemperatureBox: View {
    let info: BasicInfo
    let summary: CellSummary?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(info.temperatures.enumerated()), id: \.offset) { index, value in
                    HStack(alignment: .top) {
                        Image(systemName: "thermometer")
                            .frame(width: 20, height: 20, alignment: .center)
                        CircleNumber(number: index + 1)
                            .padding(.trailing, 4)
                        Text(info.temperatureText(value))
                            .monospacedDigit()
                        Spacer()
                    }
                }
                if info.temperatures.isEmpty {
                    Text("No temperature sensors available.")
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                if let summary {
                    HStack(alignment: .top) {
                        Image(systemName: "battery.25")
                            .frame(width: 20, height: 20, alignment: .center)
                            .rotationEffect(.degrees(-90))
                        CircleNumber(number: summary.lowestIndex + 1)
                        Text(summary.lowest.formatted(decimals: 3, unit: "V")).monospacedDigit()
                        Spacer()
                    }
                    HStack(alignment: .top) {
                        Image(systemName: "battery.75")
                            .frame(width: 20, height: 20, alignment: .center)
                            .rotationEffect(.degrees(-90))
                        CircleNumber(number: summary.highestIndex + 1)
                        Text(summary.highest.formatted(decimals: 3, unit: "V")).monospacedDigit()
                        Spacer()
                    }
                    HStack(alignment: .top) {
                        Text("△")
                            .frame(width: 20, height: 20, alignment: .center)
                        Spacer(minLength: 8)
                        Text(summary.deltaMillivolts.formatted(decimals: 0, unit: "mV")).monospacedDigit()
                        Spacer()
                    }
                }
                if info.current > 0, let remaining = info.remainingTimeText {
                    HStack(alignment: .top) {
                        Image(systemName: "clock.badge.checkmark")
                            .frame(width: 20, height: 20, alignment: .center)
                        Spacer(minLength: 8)
                        Text(remaining).monospacedDigit()
                        Spacer()
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, 4)
        }
        .padding(.horizontal)
        .padding(.top)
        .padding(.bottom, 3)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Per-cell voltages

private struct CellVoltageBox: View {
    let voltages: [Double]
    let balancing: Set<Int>
    let summary: CellSummary?
    let emptyMillivolts: Double
    let fullMillivolts: Double

    var body: some View {
        Card {
            VStack(spacing: 8) {
                ForEach(Array(voltages.enumerated()), id: \.offset) { index, voltage in
                    if voltage > 0 {
                        HStack(alignment: .center) {
                            Image(systemName: symbol(for: index))
                                .frame(width: 20, height: 20, alignment: .center)
                                .rotationEffect(.degrees(-90))
                            CircleNumber(number: index + 1)
                                .padding(.trailing, 4)
                            Text(voltage.formatted(decimals: 3, unit: "V"))
                                .monospacedDigit()
                            Spacer(minLength: 30)
                            Image(systemName: "bolt.fill")
                                .frame(width: 20, height: 20)
                                .opacity(balancing.contains(index) ? 1 : 0)
                                .animation(.easeIn(duration: 0.4), value: balancing.contains(index))
                            Spacer()
                            CellVoltageBar(fraction: fraction(for: voltage))
                                .offset(y: 6)
                        }
                    }
                }
            }
        }
    }

    private func symbol(for index: Int) -> String {
        guard let summary else { return "battery.50" }
        if index == summary.lowestIndex { return "battery.25" }
        if index == summary.highestIndex { return "battery.75" }
        return "battery.50"
    }

    private func fraction(for voltage: Double) -> Double {
        let span = fullMillivolts - emptyMillivolts
        guard span > 0 else { return 0 }
        return max(0, min((voltage * 1000 - emptyMillivolts) / span, 1))
    }
}

private struct CellVoltageBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .foregroundColor(Color.gray.opacity(0.3))
                    .cornerRadius(10)
                    .frame(height: 11)
                Rectangle()
                    .foregroundColor(Color.accentColor)
                    .cornerRadius(10)
                    .frame(width: geometry.size.width * fraction, height: 11)
            }
        }
        .frame(height: 11)
        .animation(.easeInOut(duration: 0.4), value: fraction)
    }
}

// MARK: - Pack identity and protections

private struct BatteryInfoBox: View {
    let info: BasicInfo

    var body: some View {
        Card {
            VStack(alignment: .center, spacing: 8) {
                HStack {
                    Text("Cycle count")
                    Spacer()
                    Text("\(info.cycles)")
                }
                HStack {
                    Text("Version")
                    Spacer()
                    Text(info.softwareVersion)
                }
                HStack {
                    Text("Production date")
                    Spacer()
                    Text(info.productionDate.map {
                        DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none)
                    } ?? "—")
                }
                if !info.protections.isEmpty {
                    Divider()
                    ForEach(info.protections.sorted { $0.rawValue < $1.rawValue }) { protection in
                        HStack {
                            Text(protection.label)
                            Spacer(minLength: 0)
                            Image(systemName: protection.symbol)
                                .foregroundColor(protection.tint)
                        }
                    }
                }
            }
        }
    }
}
