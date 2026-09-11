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
            if connection.openDeviceID == DemoDevice.identifier {
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
                LabeledContent("Protocol", value: connection.protocolLabel)
                if connection.supportsPasswordManagement {
                    NavigationLink {
                        PasswordSettingsView()
                    } label: {
                        LabeledContent("Hardware Password",
                                       value: connection.settings.hasPassword ? "Set" : "None")
                    }
                }
            } header: {
                Text("Device")
            } footer: {
                Text("Changing the device type allows you to access additional menus.")
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

    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        @Bindable var appSettings = appSettings

        Form {
            // The same two choices the boxes themselves offer on a long press. Kept
            // here as well because a long press advertises itself to nobody.
            Section {
                Picker("Info box", selection: $appSettings.overviewStyle) {
                    ForEach(OverviewStyle.allCases) { style in
                        Label(style.label, systemImage: style.symbol).tag(style)
                    }
                }
                Picker("Cell voltages", selection: $appSettings.storedCellVoltageStyle) {
                    Label("Automatic", systemImage: "wand.and.rays")
                        .tag(CellVoltageStyle?.none)
                    ForEach(CellVoltageStyle.allCases) { style in
                        Label(style.label, systemImage: style.symbol)
                            .tag(CellVoltageStyle?.some(style))
                    }
                }
            } header: {
                Text("Style")
            } footer: {
                Text("Long-press either box in the overview to change it from there. Automatic draws the cells as bars, or as figures alone once there are more than twenty of them.")
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
