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

    @State private var confirmation: MOSChange?

    var body: some View {
        @Bindable var connection = connection

        ScrollView {
            LazyVStack(spacing: 10) {
                DetailBox(info: connection.info,
                          capacityUnit: appSettings.capacityUnit,
                          settings: $connection.settings)
                    .padding(.top, 5)
                ButtonBox(info: connection.info,
                          settings: connection.settings,
                          enabled: connection.canControlMOS,
                          hasReading: connection.hasReading,
                          mosWrite: connection.mosWrite) { change in
                    if appSettings.showMOSFETWarning {
                        confirmation = change
                    } else {
                        connection.setMOS(terminal: change.terminal,
                                          charge: change.charge,
                                          discharge: change.discharge)
                    }
                }
                if showChargeBox {
                    ChargeBox(settings: $connection.settings)
                }
                CellTemperatureBox(info: connection.info,
                                   summary: connection.cellSummary,
                                   temperatureSummary: connection.temperatureSummary,
                                   remainingHours: connection.remainingHours)
                if !connection.cellVoltages.isEmpty {
                    CellVoltageBox(voltages: connection.cellVoltages,
                                   balancing: connection.info.balancingCells,
                                   summary: connection.cellSummary,
                                   settings: $connection.settings)
                }
                BatteryInfoBox(info: connection.info,
                               offersClearingAlerts: connection.offersClearingAlerts,
                               canClearAlerts: connection.canClearAlerts,
                               hasReading: connection.hasReading,
                               isClearingAlerts: connection.isClearingAlerts,
                               clearAlertsOutcome: connection.clearAlertsOutcome) {
                    connection.clearAlerts()
                }
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
        .confirmationDialog(confirmation?.question ?? "",
                            isPresented: Binding(get: { confirmation != nil },
                                                 set: { if !$0 { confirmation = nil } }),
                            titleVisibility: .visible) {
            if let change = confirmation {
                Button(change.confirmTitle,
                       role: change.isDisabling ? ButtonRole.destructive : nil) {
                    perform(change)
                }
                Button("\(change.confirmTitle), Don't Warn Me Again",
                       role: change.isDisabling ? ButtonRole.destructive : nil) {
                    appSettings.showMOSFETWarning = false
                    perform(change)
                }
            }
            Button("Cancel", role: .cancel) { confirmation = nil }
        } message: {
            Text("This command is written to the BMS and really cuts the current on that terminal. You can turn this warning off in Settings.")
        }
    }

    private func perform(_ change: MOSChange) {
        connection.setMOS(terminal: change.terminal, charge: change.charge, discharge: change.discharge)
        confirmation = nil
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
    var terminal: MOSWriteTracker.Terminal
    var charge: Bool
    var discharge: Bool
    var isDisabling: Bool
    var question: String
    var confirmTitle: String
}

// MARK: - Charge / discharge buttons

private struct ButtonBox: View {
    let info: BasicInfo
    let settings: DeviceSettings
    let enabled: Bool
    /// Whether the pack has said anything yet. Until it has, neither button knows
    /// what it is showing, and both say so rather than guessing.
    let hasReading: Bool
    let mosWrite: MOSWriteTracker
    let onChange: (MOSChange) -> Void

    private static let on = Color(red: 0, green: 0.6, blue: 0.1)
    private static let off = Color(red: 0.8, green: 0.3, blue: 0.05)
    /// Neither on nor off: no answer yet.
    private static let unknown = Color.gray

    /// Blue with a clock badge when the charge is being held back on purpose.
    private var chargeHeldForLater: Bool {
        settings.chargeLimitEnabled && settings.refillLaterEnabled && !info.chargeMOSEnabled
    }

    private var chargeColor: Color {
        guard hasReading else { return Self.unknown }
        if chargeHeldForLater { return .blue }
        return info.chargeMOSEnabled ? Self.on : Self.off
    }

    private var chargeSymbol: String {
        guard hasReading else { return Self.unknownSymbol }
        if chargeHeldForLater { return "bolt.badge.clock.fill" }
        return info.chargeMOSEnabled ? "bolt.fill" : "bolt.slash.fill"
    }

    private var dischargeColor: Color {
        guard hasReading else { return Self.unknown }
        return info.dischargeMOSEnabled ? Self.on : Self.off
    }

    private var dischargeSymbol: String {
        guard hasReading else { return Self.unknownSymbol }
        return info.dischargeMOSEnabled ? "bolt.fill" : "bolt.slash.fill"
    }

    /// Not the slashed bolt, which is the pack's way of saying a terminal is off —
    /// a thing we do not yet know.
    private static let unknownSymbol = "ellipsis"

    var body: some View {
        Card(padding: 0) {
            HStack(alignment: .center, spacing: 20) {
                GlassPillButton(title: "Charging",
                                color: chargeColor,
                                symbol: chargeSymbol,
                                isWaiting: mosWrite.isWaiting(for: .charge),
                                isBusy: mosWrite.isBusy) {
                    onChange(MOSChange(terminal: .charge,
                                       charge: !info.chargeMOSEnabled,
                                       discharge: info.dischargeMOSEnabled,
                                       isDisabling: info.chargeMOSEnabled,
                                       question: info.chargeMOSEnabled ? "Disable charging?" : "Enable charging?",
                                       confirmTitle: info.chargeMOSEnabled ? "Disable charging" : "Enable charging"))
                }
                GlassPillButton(title: "Discharging",
                                color: dischargeColor,
                                symbol: dischargeSymbol,
                                isWaiting: mosWrite.isWaiting(for: .discharge),
                                isBusy: mosWrite.isBusy) {
                    onChange(MOSChange(terminal: .discharge,
                                       charge: info.chargeMOSEnabled,
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

// MARK: - Temperatures and cell extremes

private struct CellTemperatureBox: View {
    let info: BasicInfo
    let summary: CellSummary?
    let temperatureSummary: TemperatureSummary?
    /// From the connection rather than from `info`: the estimate leans on the
    /// readings that came before this one as much as on this one.
    let remainingHours: Double?

    private func symbol(for index: Int) -> String {
        guard let temperatureSummary else { return "thermometer" }
        if index == temperatureSummary.lowestIndex { return "thermometer.low" }
        if index == temperatureSummary.highestIndex { return "thermometer.high" }
        return "thermometer"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(info.temperatures.enumerated()), id: \.offset) { index, value in
                    HStack(alignment: .top) {
                        Image(systemName: symbol(for: index))
                            .frame(width: 20, height: 20, alignment: .center)
                        // The pack's own name for the sensor rather than its position
                        // in the list: on a JK pack the third one is the MOSFETs, not
                        // a third probe in the cells, and numbering it "3" said
                        // otherwise.
                        CircleLabel(text: info.temperatureLabel(index))
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
                    // Tinted like the per-cell list below: the weakest cell red, the
                    // strongest green, and neither while the pack reads flat.
                    let spread = summary.highest > summary.lowest
                    HStack(alignment: .top) {
                        Image(systemName: "battery.25")
                            .frame(width: 20, height: 20, alignment: .center)
                            .rotationEffect(.degrees(-90))
                        CircleNumber(number: summary.lowestIndex + 1)
                        Text(summary.lowest.formatted(decimals: 3, unit: "V"))
                            .monospacedDigit()
                            .foregroundStyle(spread ? Color.red : Color.primary)
                        Spacer()
                    }
                    HStack(alignment: .top) {
                        Image(systemName: "battery.75")
                            .frame(width: 20, height: 20, alignment: .center)
                            .rotationEffect(.degrees(-90))
                        CircleNumber(number: summary.highestIndex + 1)
                        Text(summary.highest.formatted(decimals: 3, unit: "V"))
                            .monospacedDigit()
                            .foregroundStyle(spread ? Color.green : Color.primary)
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
                if let temperatureSummary {
                    HStack(alignment: .top) {
                        Image(systemName: "thermometer.low")
                            .frame(width: 20, height: 20, alignment: .center)
                        CircleLabel(text: info.temperatureLabel(temperatureSummary.lowestIndex))
                        Text(info.temperatureText(temperatureSummary.lowest))
                            .monospacedDigit()
                        Spacer()
                    }
                    HStack(alignment: .top) {
                        Image(systemName: "thermometer.high")
                            .frame(width: 20, height: 20, alignment: .center)
                        CircleLabel(text: info.temperatureLabel(temperatureSummary.highestIndex))
                        Text(info.temperatureText(temperatureSummary.highest))
                            .monospacedDigit()
                        Spacer()
                    }
                    HStack(alignment: .top) {
                        Text("△")
                            .frame(width: 20, height: 20, alignment: .center)
                        Spacer(minLength: 8)
                        Text("△" + String(format: "%.1f °C", temperatureSummary.delta))
                            .monospacedDigit()
                        Spacer()
                    }
                }
                if info.isBalancing {
                    HStack(alignment: .top) {
                        Image(systemName: "arrow.left.arrow.right")
                            .frame(width: 20, height: 20, alignment: .center)
                            .foregroundStyle(Color.accentColor)
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(info.balancingText)
                                .monospacedDigit()
                            // The rate, on its own line, where the pack gives one
                            // alongside the direction.
                            if info.balancingFrom != nil, let rate = info.balanceCurrentText {
                                Text(rate)
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        Spacer()
                    }
                    .transition(.opacity)
                }
                if info.current > 0, let remaining = remainingHours?.asRemainingTime {
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
            .animation(.easeInOut(duration: 0.3), value: info.isBalancing)
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

// MARK: - Pack identity and protections

private struct BatteryInfoBox: View {
    let info: BasicInfo
    /// Whether to show the reset button at all, and whether it would accept a tap
    /// right now. Two separate questions: the button has to stay on screen while the
    /// reset it started is still running, which is exactly when it refuses taps.
    let offersClearingAlerts: Bool
    let canClearAlerts: Bool
    /// Whether the pack has answered yet. The button is grey until it has, for the
    /// same reason the MOSFET pair is: nothing in this box means anything before
    /// the first frame lands.
    let hasReading: Bool
    let isClearingAlerts: Bool
    let clearAlertsOutcome: BMSConnection.WriteOutcome
    let onClearAlerts: () -> Void

    @State private var confirmingClear = false
    @State private var showingOutcome = false

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
                // Everything below here is shown only by the packs that report it,
                // rather than as a row of dashes on the ones that do not.
                if let health = info.stateOfHealth {
                    HStack {
                        Text("State of health")
                        Spacer()
                        Text("\(health) %").monospacedDigit()
                    }
                }
                if let runtime = info.totalRuntime, runtime > 0 {
                    HStack {
                        Text("Total runtime")
                        Spacer()
                        Text(runtime.asRuntime).monospacedDigit()
                    }
                }
                if let count = info.powerOnCount, count > 0 {
                    HStack {
                        Text("Power-on count")
                        Spacer()
                        Text("\(count)").monospacedDigit()
                    }
                }
                if let hardware = info.hardwareVersion, !hardware.isEmpty {
                    HStack {
                        Text("Hardware")
                        Spacer()
                        Text(hardware)
                    }
                }
                if let serial = info.serialNumber, !serial.isEmpty {
                    HStack {
                        Text("Serial number")
                        Spacer()
                        Text(serial)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
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
                if offersClearingAlerts {
                    GlassPillButton(title: "Reset alerts",
                                    color: hasReading ? .red : .gray,
                                    symbol: "exclamationmark.triangle",
                                    isWaiting: isClearingAlerts,
                                    isBusy: !canClearAlerts,
                                    size: .small) {
                        confirmingClear = true
                    }
                    .padding(.top, 2)
                    // The pill is drawn 36pt tall inside a 44pt tap target, so there
                    // is a band of empty target under it before the card's own
                    // padding even starts. Taking that back closes the gap the button
                    // was floating in — but not when the outcome note follows it,
                    // which needs the room.
                    .padding(.bottom, showingOutcome ? 0 : -8)
                    if showingOutcome {
                        outcomeNote
                    }
                }
            }
        }
        .confirmationDialog("⚠️ Reset the stored alerts?",
                            isPresented: $confirmingClear,
                            titleVisibility: .visible) {
            Button("Reset alerts", role: .destructive, action: onClearAlerts)
            Button("Cancel", role: .cancel) { confirmingClear = false }
        } message: {
            Text("This wipes the fault record the BMS keeps, and cannot be undone. A protection that is still tripped comes straight back on the next reading.")
        }
        // A refusal stays up — it is the only place it is explained. Success bows out
        // on its own rather than sitting on a dashboard that is meant to be watched.
        .task(id: clearAlertsOutcome) {
            guard clearAlertsOutcome != .idle else {
                showingOutcome = false
                return
            }
            showingOutcome = true
            guard clearAlertsOutcome == .succeeded else { return }
            try? await Task.sleep(for: .seconds(4))
            showingOutcome = false
        }
    }

    /// The line under the button, once there is something to say about the last reset.
    @ViewBuilder
    private var outcomeNote: some View {
        switch clearAlertsOutcome {
        case .idle:
            EmptyView()
        case .succeeded:
            note("The BMS cleared its stored alerts.", tint: .green)
        case .rejected(let message):
            note(message, tint: .red)
        }
    }

    private func note(_ message: String, tint: Color) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(tint)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}
