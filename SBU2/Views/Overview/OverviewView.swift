//
//  OverviewView.swift
//  SBU2
//

import SwiftUI

/// The live dashboard: state of charge, MOSFET control, cell figures and pack identity.
struct OverviewView: View {
    @Environment(BMSConnection.self) private var connection
    @Environment(AppSettings.self) private var appSettings

    @State private var pendingMOS: MOSChange?

    var body: some View {
        @Bindable var connection = connection

        ScrollView {
            LazyVStack(spacing: 12) {
                if !connection.status.isConnected {
                    ConnectingCard(status: connection.status)
                }

                if connection.settings.liontronMode == .autoEnabled {
                    LiontronWarningCard()
                }

                SummaryCard(info: connection.info, capacityUnit: appSettings.capacityUnit)

                MOSCard(info: connection.info,
                        enabled: connection.canControlMOS && !connection.isWritingMOS) { change in
                    pendingMOS = change
                }

                if shouldShowChargeLimit {
                    ChargeLimitCard(settings: $connection.settings)
                }

                CellSummaryCard(info: connection.info,
                                summary: connection.cellSummary,
                                remainingTime: connection.info.remainingTimeText)

                if !connection.cellVoltages.isEmpty {
                    CellVoltageCard(voltages: connection.cellVoltages,
                                    balancing: connection.info.balancingCells,
                                    emptyMillivolts: Double(connection.settings.cellEmptyVoltage),
                                    fullMillivolts: Double(connection.settings.cellFullVoltage))
                }

                BatteryInfoCard(info: connection.info)

                if let error = connection.lastError {
                    Card {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .scrollDismissesKeyboard(.interactively)
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
            Button("Annuler", role: .cancel) { pendingMOS = nil }
        } message: {
            Text("Cette commande est écrite dans le BMS et coupe réellement le courant sur la borne concernée.")
        }
    }

    private var shouldShowChargeLimit: Bool {
        guard connection.settings.chargeLimitEnabled else { return false }
        return connection.info.current > 0 || connection.settings.alwaysShowChargeLimit
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

// MARK: - Cards

private struct ConnectingCard: View {
    let status: BMSConnection.Status

    var body: some View {
        Card {
            HStack(spacing: 12) {
                ProgressView()
                Text(message)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private var message: String {
        switch status {
        case .connecting(let name): return "Connexion à \(name)…"
        case .bluetoothOff: return "Bluetooth désactivé."
        default: return "Appareil non connecté."
        }
    }
}

private struct LiontronWarningCard: View {
    @State private var expanded = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                            .foregroundStyle(.orange)
                        Text("Protection Liontron active")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                if expanded {
                    Text("Ce pack a refusé une écriture. Saisissez son mot de passe matériel dans Réglages pour réactiver les commandes MOSFET.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct SummaryCard: View {
    let info: BasicInfo
    let capacityUnit: CapacityUnit

    var body: some View {
        Card {
            VStack(spacing: 14) {
                HStack(spacing: 18) {
                    RingGauge(fraction: Double(info.stateOfCharge) / 100,
                              tint: .forStateOfCharge(info.stateOfCharge)) {
                        Text(info.stateOfChargeText)
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                    .frame(width: 116, height: 116)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(info.powerText)
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(info.current >= 0 ? Color.green : Color.primary)
                        LabelledValue(title: "Courant", value: info.currentText)
                        LabelledValue(title: "Tension", value: info.voltageText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                LabelledValue(title: "Capacité", value: info.capacityText(unit: capacityUnit))
                if let remaining = info.remainingTimeText {
                    LabelledValue(title: info.current > 0 ? "Charge complète dans" : "Autonomie restante",
                                  value: remaining)
                }
            }
        }
    }
}

private struct LabelledValue: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }
}

private struct MOSCard: View {
    let info: BasicInfo
    let enabled: Bool
    let onChange: (MOSChange) -> Void

    var body: some View {
        Card {
            HStack(spacing: 12) {
                MOSButton(title: "Charge",
                          isOn: info.chargeMOSEnabled,
                          enabled: enabled) {
                    onChange(MOSChange(charge: !info.chargeMOSEnabled,
                                       discharge: info.dischargeMOSEnabled,
                                       isDisabling: info.chargeMOSEnabled,
                                       question: info.chargeMOSEnabled ? "Couper la charge ?" : "Activer la charge ?",
                                       confirmTitle: info.chargeMOSEnabled ? "Couper la charge" : "Activer la charge"))
                }
                MOSButton(title: "Décharge",
                          isOn: info.dischargeMOSEnabled,
                          enabled: enabled) {
                    onChange(MOSChange(charge: info.chargeMOSEnabled,
                                       discharge: !info.dischargeMOSEnabled,
                                       isDisabling: info.dischargeMOSEnabled,
                                       question: info.dischargeMOSEnabled ? "Couper la décharge ?" : "Activer la décharge ?",
                                       confirmTitle: info.dischargeMOSEnabled ? "Couper la décharge" : "Activer la décharge"))
                }
            }
        }
    }
}

private struct MOSButton: View {
    let title: String
    let isOn: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "bolt.fill" : "bolt.slash.fill")
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 38)
        }
        .buttonStyle(.borderedProminent)
        .tint(enabled ? (isOn ? .green : .orange) : .gray)
        .disabled(!enabled)
        .animation(.easeInOut(duration: 0.25), value: isOn)
        .accessibilityLabel("\(title) : \(isOn ? "activée" : "coupée")")
    }
}

private struct CellSummaryCard: View {
    let info: BasicInfo
    let summary: CellSummary?
    let remainingTime: String?

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    if info.temperatures.isEmpty {
                        Text("Aucune sonde de température")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(info.temperatures.enumerated()), id: \.offset) { index, value in
                        HStack(spacing: 8) {
                            Image(systemName: "thermometer.medium")
                                .frame(width: 18)
                                .foregroundStyle(.secondary)
                            IndexBadge(number: index + 1)
                            Text(info.temperatureText(value)).monospacedDigit()
                            Spacer(minLength: 0)
                        }
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Sonde \(index + 1), \(info.temperatureText(value))")
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    if let summary {
                        CellExtremeRow(systemImage: "arrow.down.to.line",
                                       index: summary.lowestIndex + 1,
                                       value: summary.lowest.formatted(decimals: 3, unit: "V"),
                                       tint: .orange,
                                       accessibility: "Cellule la plus basse")
                        CellExtremeRow(systemImage: "arrow.up.to.line",
                                       index: summary.highestIndex + 1,
                                       value: summary.highest.formatted(decimals: 3, unit: "V"),
                                       tint: .green,
                                       accessibility: "Cellule la plus haute")
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.and.down")
                                .frame(width: 18)
                                .foregroundStyle(.secondary)
                            Text("Écart")
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Text(summary.deltaMillivolts.formatted(decimals: 0, unit: "mV"))
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                    } else {
                        Text("Tensions de cellule indisponibles")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let remainingTime {
                        HStack(spacing: 8) {
                            Image(systemName: "clock")
                                .frame(width: 18)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Text(remainingTime).monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct CellExtremeRow: View {
    let systemImage: String
    let index: Int
    let value: String
    let tint: Color
    let accessibility: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 18)
                .foregroundStyle(tint)
            IndexBadge(number: index)
            Text(value).monospacedDigit()
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(accessibility) : cellule \(index), \(value)")
    }
}

private struct CellVoltageCard: View {
    let voltages: [Double]
    let balancing: Set<Int>
    let emptyMillivolts: Double
    let fullMillivolts: Double

    var body: some View {
        Card {
            VStack(spacing: 10) {
                ForEach(Array(voltages.enumerated()), id: \.offset) { index, voltage in
                    HStack(spacing: 8) {
                        IndexBadge(number: index + 1)
                        Text(voltage.formatted(decimals: 3, unit: "V"))
                            .font(.subheadline)
                            .monospacedDigit()
                            .frame(width: 74, alignment: .leading)
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .opacity(balancing.contains(index) ? 1 : 0)
                            .accessibilityHidden(!balancing.contains(index))
                            .accessibilityLabel("Équilibrage en cours")
                        CellBar(fraction: fraction(for: voltage))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// Where the cell sits between the configured empty and full voltages.
    private func fraction(for voltage: Double) -> Double {
        let span = fullMillivolts - emptyMillivolts
        guard span > 0 else { return 0 }
        return max(0, min((voltage * 1000 - emptyMillivolts) / span, 1))
    }
}

private struct CellBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 10)
        .animation(.easeInOut(duration: 0.4), value: fraction)
    }
}

private struct BatteryInfoCard: View {
    let info: BasicInfo

    var body: some View {
        Card {
            VStack(spacing: 10) {
                LabelledValue(title: "Cellules", value: "\(info.cellCount)")
                LabelledValue(title: "Cycles", value: "\(info.cycles)")
                if !info.softwareVersion.isEmpty {
                    LabelledValue(title: "Version", value: info.softwareVersion)
                }
                if let date = info.productionDate {
                    LabelledValue(title: "Fabrication",
                                  value: date.formatted(date: .abbreviated, time: .omitted))
                }

                if !info.protections.isEmpty {
                    Divider()
                    ForEach(info.protections.sorted { $0.rawValue < $1.rawValue }) { protection in
                        HStack {
                            Text(protection.label)
                            Spacer(minLength: 8)
                            Image(systemName: protection.isCritical
                                  ? "exclamationmark.triangle.fill"
                                  : "info.circle.fill")
                        }
                        .font(.subheadline)
                        .foregroundStyle(protection.isCritical ? Color.red : Color.secondary)
                    }
                }
            }
        }
    }
}
