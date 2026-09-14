//
//  DeviceSettingsView.swift
//  SBU2
//

import SwiftUI

/// Per-device preferences — the "More" tab of SBU.
struct DeviceSettingsView: View {
    @Environment(BMSConnection.self) private var connection

    var body: some View {
        @Bindable var connection = connection

        Form {
            if connection.isDemoOpen {
                Section {
                    Label("Demo device: values are simulated and no command is sent.",
                          systemImage: "wand.and.sparkles")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Device name") {
                    TextField("Device name", text: $connection.settings.name)
                        .multilineTextAlignment(.trailing)
                }
                Picker("Type of Device", selection: $connection.settings.kind) {
                    ForEach(DeviceKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                Toggle("Auto connect", isOn: $connection.settings.autoConnect)
                // The simulated pack has no advertisement to be recognised by, so it
                // is the one device whose family is chosen rather than detected.
                if connection.isDemoOpen {
                    Picker("Protocol", selection: $connection.demoFamily) {
                        ForEach(BMSProtocolID.allCases) { id in
                            Text(BMSProtocolRegistry.descriptor(for: id).label).tag(id)
                        }
                    }
                } else {
                    LabeledContent("Protocol", value: connection.protocolLabel)
                }
                if connection.supportsPasswordManagement {
                    NavigationLink {
                        PasswordSettingsView()
                    } label: {
                        LabeledContent("Hardware Password",
                                       value: connection.settings.hasPassword ? "Set" : "None")
                    }
                }
                // What the pack says it is. Only the rows it actually answers — a
                // family or a firmware that keeps one of these to itself shows no row
                // rather than a dash. None of them ever change while the app is open,
                // which is why they sit here rather than in the overview.
                IdentityRow(title: "Model", value: connection.info.model)
                IdentityRow(title: "Hardware Version", value: connection.info.hardwareVersion)
                IdentityRow(title: "Serial Number", value: connection.info.serialNumber)
            } header: {
                Text("Device")
            } footer: {
                Text(connection.isDemoOpen
                     ? "Changing the device type allows you to access additional menus. The protocol decides which family the simulated pack imitates: the two do not measure the same things and do not accept the same commands, so switching is how to see what each one offers without the hardware."
                     : "Changing the device type allows you to access additional menus.")
            }

            // Out of the GPS section, which only vehicles see: the overview's power
            // bar is scaled against this too, and every kind of pack has one of those.
            Section {
                LabeledContent("Nominal Power") {
                    HStack(spacing: 4) {
                        TextField("1000", value: $connection.settings.expectedPower, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                        Text("W").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Power")
            } footer: {
                Text("What this pack draws when it is working hard. It sets the full scale of the power bar in the overview, and of the power dial on the GPS screen.")
            }

            if connection.settings.kind == .vehicle {
                Section {
                    LabeledContent("Expected Range") {
                        HStack(spacing: 4) {
                            TextField("65", value: $connection.settings.expectedRange, format: .number)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numberPad)
                            Text(Locale.current.preferredDistanceUnit.symbol)
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink("Customize Dials") {
                        DialsSettingsView(settings: $connection.settings)
                    }
                } header: {
                    Text("GPS")
                } footer: {
                    Text("Expected Range calibrates the remaining range gauge in the GPS menu. This allows you to see if you are consuming more or less than expected.")
                }
            }

            Section("Overview") {
                NavigationLink("Customize Overview") {
                    OverviewSettingsView(settings: $connection.settings)
                }
            }

            if connection.supportsCalibration {
                Section {
                    NavigationLink("Calibration") {
                        CalibrationSettingsView()
                    }
                } header: {
                    Text("Measurement")
                } footer: {
                    Text("Tells the BMS what its readings should really be. Every protection is decided from those readings, so this is worth doing only with a meter in hand.")
                }
            }

            Section {
                Toggle("Charge Limit", isOn: $connection.settings.chargeLimitEnabled)
                Picker("Cell chemistry", selection: $connection.settings.chemistry) {
                    ForEach(CellChemistry.allCases) { chemistry in
                        Text(chemistry.label).tag(chemistry)
                    }
                }
                MillivoltField(title: "Cell empty voltage", value: $connection.settings.cellEmptyVoltage)
                MillivoltField(title: "Cell nominal voltage", value: $connection.settings.cellNominalVoltage)
                MillivoltField(title: "Cell full voltage", value: $connection.settings.cellFullVoltage)
            } header: {
                Text("Charge")
            } footer: {
                Text("Charge Limit allows you to stop the charge at a certain chosen value. The function appears when the battery is charging. The empty and full voltages also scale the cell voltage bars in Overview. The chemistry decides how the remaining charge time is worked out: an LFP pack charges at a steady current almost to the top, a Li-ion one starts slowing down with a quarter still to go.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One thing the pack says about itself, or nothing at all.
///
/// Long strings are the norm here — a JBD model name runs to twenty-five characters
/// and a serial number further — so the value wraps rather than being cut off, and is
/// selectable, because a serial number is something people copy.
private struct IdentityRow: View {
    let title: String
    let value: String?

    var body: some View {
        if let value, !value.isEmpty {
            LabeledContent(title) {
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct MillivoltField: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField("3200", value: $value, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
                Text("mV").foregroundStyle(.secondary)
            }
        }
    }
}

/// Which trip dials are shown.
struct DialsSettingsView: View {
    @Binding var settings: DeviceSettings

    var body: some View {
        Form {
            Section {
                Toggle("Power dial", isOn: $settings.showPowerDial)
                    .tint(.accent)
                Toggle("Speed dial", isOn: $settings.showSpeedDial)
                    .tint(.accent)
                Toggle("Remaining Range dial", isOn: $settings.showRangeDial)
                    .tint(.accent)
            } footer: {
                Text("When a dial is disabled, the information is still visible in the list below the dials.")
            }
        }
        .navigationTitle("Dials")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Overview appearance options.
struct OverviewSettingsView: View {
    @Binding var settings: DeviceSettings

    var body: some View {
        Form {
            // The same two choices the boxes themselves offer on a long press. Kept
            // here as well because a long press advertises itself to nobody.
            Section {
                Picker("Info box", selection: $settings.overviewStyle) {
                    ForEach(OverviewStyle.allCases) { style in
                        Label(style.label, systemImage: style.symbol).tag(style)
                    }
                }
                Picker("Cell voltages", selection: $settings.cellVoltageStyle) {
                    ForEach(CellVoltageStyle.allCases) { style in
                        Label(style.label, systemImage: style.symbol).tag(style)
                    }
                }
            } header: {
                Text("Style")
            } footer: {
                Text("Long-press either box in the overview to change it from there. The cell style starts as bars, or as figures alone on a pack of more than twenty cells, the first time the pack is read.")
            }

            Section {
                Toggle("Always show charge limit", isOn: $settings.alwaysShowChargeLimit)
                    .disabled(!settings.chargeLimitEnabled)
            } header: {
                Text("Charge Limit Settings")
            } footer: {
                Text(settings.chargeLimitEnabled
                     ? "Show charging limit even when the battery is not charging."
                     : "Enable Charge Limit in the device settings first.")
            }
        }
        .navigationTitle("Overview")
        .navigationBarTitleDisplayMode(.inline)
    }
}
