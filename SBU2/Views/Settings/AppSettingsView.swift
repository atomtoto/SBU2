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
                Toggle("Appareil de démonstration", isOn: $settings.showDemoDevice)
            } header: {
                Text("Connexion")
            } footer: {
                Text("Ajoute un pack simulé à la liste pour explorer l'application sans BMS à portée.")
            }

            Section {
                Picker("Unité de capacité", selection: $settings.capacityUnit) {
                    ForEach(CapacityUnit.allCases) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Unités")
            } footer: {
                Text("Change l'affichage de la capacité restante dans l'overview. Les kWh sont estimés à partir de la tension mesurée du pack.")
            }

            Section {
                Toggle("Empêcher la mise en veille", isOn: $settings.keepScreenAwake)
            } header: {
                Text("Écran")
            } footer: {
                Text("Garde l'écran allumé tant que l'application est au premier plan.")
            }

            Section("Apparence") {
                Picker("Thème", selection: $settings.appearance) {
                    ForEach(Appearance.allCases) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Application") {
                NavigationLink {
                    AboutView()
                } label: {
                    Label("À propos", systemImage: "info.circle")
                }
                LabeledContent("Version", value: AppSettings.versionString)
            }
        }
        .navigationTitle("Réglages")
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
                Text("Application de supervision pour les BMS JBD, également vendus sous les noms Xiaoxiang, Overkill Solar ou LLT Power.")
            }

            Section("Protocole") {
                LabeledContent("Service BLE", value: "FF00")
                LabeledContent("Notifications", value: "FF01")
                LabeledContent("Écriture", value: "FF02")
            }

            Section {
                Label("Les commandes MOSFET coupent réellement le courant du pack. Vérifiez ce qui y est branché avant de les utiliser.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .navigationTitle("À propos")
        .navigationBarTitleDisplayMode(.inline)
    }
}
