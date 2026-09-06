//
//  AppSettingsView.swift
//  SBU2
//

import SwiftUI

/// App-wide preferences, reached from the gear on the device list.
struct AppSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Enable Demo Device", isOn: $settings.showDemoDevice)
            } header: {
                Text("Connection")
            } footer: {
                Text("Adds a simulated pack to the list so you can explore the app with no BMS in range.")
            }

            Section {
                Picker("Preferred capacity unit", selection: $settings.capacityUnit) {
                    ForEach(CapacityUnit.allCases) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Units")
            } footer: {
                Text("This changes the display of the remaining capacity in Overview. kWh are estimated from the measured pack voltage.")
            }

            Section {
                Toggle("Disable automatic standby", isOn: $settings.keepScreenAwake)
            } header: {
                Text("Sleep")
            } footer: {
                Text("Keeps the screen awake while the app is in the foreground.")
            }

            Section("Theme") {
                Picker("Select Theme", selection: $settings.appearance) {
                    ForEach(Appearance.allCases) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("App") {
                NavigationLink {
                    AboutView()
                } label: {
                    Label("About this app", systemImage: "info.circle")
                }
                LabeledContent("Version", value: AppSettings.versionString)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutView: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "minus.plus.batteryblock.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.accentColor)
                    Text("SBU2")
                        .font(.title2.weight(.semibold))
                    Text("Version \(AppSettings.versionString)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            Section {
                Text("Monitoring app for JBD smart BMS, also sold as Xiaoxiang, Overkill Solar or LLT Power.")
            }

            Section("Protocol") {
                LabeledContent("BLE service", value: "FF00")
                LabeledContent("Notify", value: "FF01")
                LabeledContent("Write", value: "FF02")
            }

            Section {
                Label("The MOSFET commands really cut the pack current. Check what is connected before using them.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .navigationTitle("About this app")
        .navigationBarTitleDisplayMode(.inline)
    }
}
