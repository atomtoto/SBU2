//
//  ScanView.swift
//  SBU2
//

import SwiftUI

/// Root screen: lists the JBD dongles in range and opens the monitor once connected.
struct ScanView: View {
    @Environment(BMSConnection.self) private var connection
    @State private var selected: DiscoveredBMS?

    var body: some View {
        NavigationStack {
            List {
                if let message = unavailableMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(connection.discovered) { device in
                            Button {
                                selected = device
                                connection.connect(to: device)
                            } label: {
                                DeviceRow(device: device)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Appareils détectés")
                    } footer: {
                        if connection.discovered.isEmpty {
                            Text("Recherche des BMS à proximité… Vérifiez que le module Bluetooth est alimenté et hors de portée de toute autre application connectée.")
                        }
                    }
                }

                if let error = connection.lastError {
                    Section("Dernière erreur") {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Smart BMS")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if connection.status == .scanning {
                        ProgressView()
                    } else {
                        Button("Rechercher", systemImage: "arrow.clockwise") {
                            connection.startScanning()
                        }
                    }
                }
            }
            .refreshable { connection.startScanning() }
            .navigationDestination(item: $selected) { device in
                MonitorView(deviceName: device.name)
            }
            .onChange(of: selected) { _, newValue in
                if newValue == nil { connection.disconnect() }
            }
        }
    }

    private var unavailableMessage: String? {
        switch connection.status {
        case .bluetoothOff:
            return "Le Bluetooth est désactivé."
        case .unauthorized:
            return "SBU2 n'est pas autorisée à utiliser le Bluetooth. Activez l'accès dans Réglages."
        case .unsupported:
            return "Cet appareil ne prend pas en charge le Bluetooth LE."
        default:
            return nil
        }
    }
}

private struct DeviceRow: View {
    let device: DiscoveredBMS

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                Text(device.id.uuidString)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(device.rssi) dBm")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
