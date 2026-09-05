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
                    Label("Appareil de démonstration : les valeurs sont simulées et aucune commande n'est envoyée.",
                          systemImage: "wand.and.sparkles")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Nom") {
                    TextField("Nom de l'appareil", text: $connection.settings.name)
                        .multilineTextAlignment(.trailing)
                }
                Picker("Type d'appareil", selection: $connection.settings.kind) {
                    ForEach(DeviceKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                Toggle("Connexion automatique", isOn: $connection.settings.autoConnect)
                NavigationLink {
                    PasswordSettingsView()
                } label: {
                    LabeledContent("Mot de passe matériel",
                                   value: connection.settings.hasPassword ? "Défini" : "Aucun")
                }
            } header: {
                Text("Appareil")
            } footer: {
                Text("Le type d'appareil détermine les onglets disponibles : un véhicule ajoute l'onglet Trajet.")
            }

            if connection.settings.kind == .vehicle {
                Section {
                    LabeledContent("Puissance nominale") {
                        HStack(spacing: 4) {
                            TextField("1000", value: $connection.settings.expectedPower, format: .number)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numberPad)
                            Text("W").foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Autonomie attendue") {
                        HStack(spacing: 4) {
                            TextField("65", value: $connection.settings.expectedRange, format: .number)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numberPad)
                            Text(Locale.current.preferredDistanceUnit.symbol)
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink("Personnaliser les cadrans") {
                        DialsSettingsView(settings: $connection.settings)
                    }
                } header: {
                    Text("Trajet")
                } footer: {
                    Text("L'autonomie attendue calibre le cadran d'autonomie : vous voyez ainsi si vous consommez plus ou moins que prévu.")
                }
            }

            Section("Overview") {
                NavigationLink("Personnaliser l'overview") {
                    OverviewSettingsView(settings: $connection.settings)
                }
            }

            Section {
                Picker("Mode Liontron", selection: $connection.settings.liontronMode) {
                    ForEach(LiontronMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            } header: {
                Text("Sécurité")
            } footer: {
                Text("Certains packs Liontron refusent toute écriture tant que leur mot de passe matériel n'a pas été saisi. En mode auto, l'application désactive les boutons MOSFET dès qu'un refus est détecté.")
            }

            Section {
                Toggle("Limite de charge", isOn: $connection.settings.chargeLimitEnabled)
                MillivoltField(title: "Tension cellule vide", value: $connection.settings.cellEmptyVoltage)
                MillivoltField(title: "Tension cellule nominale", value: $connection.settings.cellNominalVoltage)
                MillivoltField(title: "Tension cellule pleine", value: $connection.settings.cellFullVoltage)
            } header: {
                Text("Charge")
            } footer: {
                Text("Les tensions vide et pleine servent d'échelle aux barres de tension dans l'overview.")
            }
        }
        .navigationTitle("Réglages")
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
                Toggle("Cadran de puissance", isOn: $settings.showPowerDial)
                Toggle("Cadran de vitesse", isOn: $settings.showSpeedDial)
                Toggle("Cadran d'autonomie", isOn: $settings.showRangeDial)
            } footer: {
                Text("Une valeur dont le cadran est masqué reste visible dans la liste en dessous.")
            }
        }
        .navigationTitle("Cadrans")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Overview appearance options.
struct OverviewSettingsView: View {
    @Binding var settings: DeviceSettings

    var body: some View {
        Form {
            Section {
                Toggle("Toujours afficher la limite de charge",
                       isOn: $settings.alwaysShowChargeLimit)
                    .disabled(!settings.chargeLimitEnabled)
            } header: {
                Text("Limite de charge")
            } footer: {
                Text(settings.chargeLimitEnabled
                     ? "Affiche la limite même lorsque la batterie n'est pas en charge."
                     : "Activez d'abord la limite de charge dans les réglages de l'appareil.")
            }
        }
        .navigationTitle("Overview")
        .navigationBarTitleDisplayMode(.inline)
    }
}
