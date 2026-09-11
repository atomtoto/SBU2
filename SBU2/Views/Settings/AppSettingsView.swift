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

            Section {
                Toggle("Confirm before switching MOSFETs", isOn: $settings.showMOSFETWarning)
            } header: {
                Text("Safety")
            } footer: {
                Text("Shows a warning before every charge or discharge command. Turning this off applies the command as soon as you tap the button.")
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
                Text("Reads smart battery management systems over Bluetooth: what the cells are doing, what the pack is doing, and — where the pack allows it — switching its terminals.")
            }

            Section {
                ForEach(families) { family in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(family.label)
                        Text(family.controls)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(family.profile)
                            .font(.caption2)
                            .monospaced()
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Packs it speaks to")
            } footer: {
                Text("Which family a pack belongs to is worked out from what it advertises, so there is nothing to choose. A pack is listed only when one of them recognises it.")
            }

            Section {
                tip("Long-press the top box or the cell voltages in Overview to change how they are drawn.",
                    systemImage: "hand.tap")
                tip("Long-press a pack on the home screen to give it a symbol, an emoji or a Genmoji.",
                    systemImage: "face.smiling")
                tip("Turn the phone sideways on the GPS screen: three dials fit better in landscape.",
                    systemImage: "iphone.landscape")
            } header: {
                Text("Things that are easy to miss")
            }

            Section {
                Text("The charge limit and the scheduled refill are remembered, but nothing acts on them yet. iOS gives no app a guarantee of running long enough in the background to catch a pack at a given level, so arming one here does not stop a charge.")
                Text("The remaining time follows the curve a lithium pack really charges along — steady current up to a point, then tapering — rather than dividing what is missing by the current of the moment. It still trusts the pack's own state of charge, so a BMS whose counting has drifted will be confidently wrong about the quantity.")
                Text("Calibration tells the BMS what its readings should really be, and every protection it has is decided from those readings. It is worth doing only with a meter in hand.")
            } header: {
                Text("Worth knowing")
            }

            Section {
                Label("The charge and discharge buttons really cut the current at that terminal. Check what is connected to the pack before using them.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .navigationTitle("About this app")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tip(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text).font(.footnote)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(Color.accentColor)
        }
    }

    /// One supported family, read off the registry rather than written out here, so
    /// this page cannot quietly fall behind the code the way it had.
    private struct Family: Identifiable {
        var id: String
        var label: String
        var controls: String
        var profile: String
    }

    private var families: [Family] {
        BMSProtocolRegistry.descriptors.map { descriptor in
            let adapter = descriptor.make()
            var writes: [String] = []
            if adapter.supportsMOSControl { writes.append("charge and discharge switching") }
            if adapter.supportsClearingAlerts { writes.append("alert reset") }
            if adapter.supportsCalibration { writes.append("calibration") }
            if adapter.supportsPasswordManagement { writes.append("hardware password") }

            let profile = descriptor.profile
            let characteristics = profile.notify == profile.write
                ? profile.notify.uuidString
                : "\(profile.notify.uuidString) / \(profile.write.uuidString)"

            return Family(id: descriptor.id.rawValue,
                          label: descriptor.label,
                          controls: writes.isEmpty
                              ? "Readings only — nothing is written to this pack."
                              : "Readings, plus " + writes.joined(separator: ", ") + ".",
                          profile: "Service \(profile.service.uuidString) · \(characteristics)")
        }
    }
}
