//
//  MonitorView.swift
//  SBU2
//

import SwiftUI

/// Live view of the connected pack: state of charge, per-cell voltages,
/// temperatures, active protections and MOSFET control.
struct MonitorView: View {
    @Environment(BMSConnection.self) private var connection

    let deviceName: String

    @State private var pendingMOS: MOSChange?

    var body: some View {
        List {
            if !connection.status.isConnected {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Connexion à \(deviceName)…")
                    }
                }
            }

            SummarySection(info: connection.info)

            if !connection.info.protections.isEmpty {
                Section("Protections actives") {
                    ForEach(Array(connection.info.protections).sorted { $0.rawValue < $1.rawValue }) { protection in
                        Label(protection.label,
                              systemImage: protection.isCritical ? "exclamationmark.triangle.fill" : "info.circle")
                            .foregroundStyle(protection.isCritical ? Color.red : Color.secondary)
                    }
                }
            }

            if !connection.cellVoltages.isEmpty {
                CellSection(voltages: connection.cellVoltages,
                            balancing: connection.info.balancingCells)
            }

            if !connection.info.temperatures.isEmpty {
                Section("Températures") {
                    ForEach(Array(connection.info.temperatures.enumerated()), id: \.offset) { index, value in
                        LabeledContent("Sonde \(index + 1)",
                                       value: value.formatted(.number.precision(.fractionLength(1))) + " °C")
                    }
                }
            }

            MOSSection(info: connection.info,
                       isWriting: connection.isWritingMOS,
                       isConnected: connection.status.isConnected) { change in
                pendingMOS = change
            }

            DetailsSection(info: connection.info, lastUpdate: connection.lastUpdate)

            if let error = connection.lastError {
                Section("Erreur") {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(deviceName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(pendingMOS?.question ?? "",
                            isPresented: Binding(get: { pendingMOS != nil },
                                                 set: { if !$0 { pendingMOS = nil } }),
                            titleVisibility: .visible) {
            if let change = pendingMOS {
                Button(change.confirmTitle, role: change.isDisabling ? ButtonRole.destructive : nil) {
                    connection.setMOS(charge: change.charge, discharge: change.discharge)
                    pendingMOS = nil
                }
            }
            Button("Annuler", role: .cancel) { pendingMOS = nil }
        } message: {
            Text("Cette commande est écrite dans le BMS et coupe réellement le courant sur la borne concernée.")
        }
    }
}

/// A requested MOSFET state, held until the user confirms it.
struct MOSChange: Equatable {
    var charge: Bool
    var discharge: Bool
    /// Which of the two switches the user just moved.
    var isDisabling: Bool
    var question: String
    var confirmTitle: String
}

// MARK: - Sections

private struct SummarySection: View {
    let info: BasicInfo

    var body: some View {
        Section {
            HStack(alignment: .center, spacing: 20) {
                Gauge(value: Double(info.stateOfCharge), in: 0...100) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(info.stateOfCharge)")
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(socColor)

                VStack(alignment: .leading, spacing: 6) {
                    ValueRow(title: "Tension",
                             value: info.packVoltage.formatted(.number.precision(.fractionLength(2))) + " V")
                    ValueRow(title: "Courant",
                             value: info.current.formatted(.number.precision(.fractionLength(2))) + " A")
                    ValueRow(title: "Puissance",
                             value: info.power.formatted(.number.precision(.fractionLength(1))) + " W")
                }
            }
            .padding(.vertical, 4)

            LabeledContent("Capacité",
                           value: "\(info.residualCapacity.formatted(.number.precision(.fractionLength(2)))) / \(info.nominalCapacity.formatted(.number.precision(.fractionLength(2)))) Ah")

            if let hours = info.remainingHours {
                LabeledContent(info.current > 0 ? "Charge complète dans" : "Autonomie restante",
                               value: Self.format(hours: hours))
            }
        }
    }

    private var socColor: Color {
        switch info.stateOfCharge {
        case ..<20: .red
        case ..<50: .orange
        default: .green
        }
    }

    static func format(hours: Double) -> String {
        let total = Int((hours * 60).rounded())
        let (h, m) = (total / 60, total % 60)
        return h > 0 ? "\(h) h \(m) min" : "\(m) min"
    }
}

private struct ValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }
}

private struct CellSection: View {
    let voltages: [Double]
    let balancing: Set<Int>

    var body: some View {
        Section {
            ForEach(Array(voltages.enumerated()), id: \.offset) { index, voltage in
                HStack {
                    Text("Cellule \(index + 1)")
                    if balancing.contains(index) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Équilibrage en cours")
                    }
                    Spacer()
                    Text(voltage.formatted(.number.precision(.fractionLength(3))) + " V")
                        .monospacedDigit()
                        .foregroundStyle(color(for: voltage))
                }
            }
        } header: {
            Text("Cellules")
        } footer: {
            if let low = voltages.min(), let high = voltages.max() {
                Text("Écart max : \(((high - low) * 1000).formatted(.number.precision(.fractionLength(0)))) mV")
            }
        }
    }

    private func color(for voltage: Double) -> Color {
        guard let low = voltages.min(), let high = voltages.max(), high > low else { return .primary }
        if voltage == high { return .green }
        if voltage == low { return .orange }
        return .primary
    }
}

private struct MOSSection: View {
    let info: BasicInfo
    let isWriting: Bool
    let isConnected: Bool
    let onChange: (MOSChange) -> Void

    var body: some View {
        Section {
            Toggle("Charge", isOn: Binding(
                get: { info.chargeMOSEnabled },
                set: { newValue in
                    onChange(MOSChange(charge: newValue,
                                       discharge: info.dischargeMOSEnabled,
                                       isDisabling: !newValue,
                                       question: newValue ? "Activer la charge ?" : "Couper la charge ?",
                                       confirmTitle: newValue ? "Activer la charge" : "Couper la charge"))
                }))

            Toggle("Décharge", isOn: Binding(
                get: { info.dischargeMOSEnabled },
                set: { newValue in
                    onChange(MOSChange(charge: info.chargeMOSEnabled,
                                       discharge: newValue,
                                       isDisabling: !newValue,
                                       question: newValue ? "Activer la décharge ?" : "Couper la décharge ?",
                                       confirmTitle: newValue ? "Activer la décharge" : "Couper la décharge"))
                }))
        } header: {
            Text("MOSFET")
        } footer: {
            Text("Certains BMS refusent ces commandes tant qu'un mot de passe est configuré.")
        }
        .disabled(isWriting || !isConnected)
    }
}

private struct DetailsSection: View {
    let info: BasicInfo
    let lastUpdate: Date?

    var body: some View {
        Section("Informations") {
            LabeledContent("Cellules", value: "\(info.cellCount)")
            LabeledContent("Cycles", value: "\(info.cycles)")
            if !info.softwareVersion.isEmpty {
                LabeledContent("Version", value: info.softwareVersion)
            }
            if let date = info.productionDate {
                LabeledContent("Fabrication", value: date.formatted(date: .abbreviated, time: .omitted))
            }
            if let lastUpdate {
                LabeledContent("Dernière mesure",
                               value: lastUpdate.formatted(date: .omitted, time: .standard))
            }
        }
    }
}
