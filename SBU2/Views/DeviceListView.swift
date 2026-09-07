//
//  DeviceListView.swift
//  SBU2
//

import SwiftUI

/// Root screen: the packs in range, as a grid of cards.
struct DeviceListView: View {
    @Environment(BMSConnection.self) private var connection
    @Environment(AppSettings.self) private var appSettings

    @State private var opened: DiscoveredBMS?
    @State private var showingSettings = false
    @State private var hasAutoConnected = false

    private let columns = [GridItem(.adaptive(minimum: 165), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if let message = unavailableMessage {
                    ContentUnavailableView("Bluetooth unavailable",
                                           systemImage: "antenna.radiowaves.left.and.right.slash",
                                           description: Text(message))
                } else if connection.discovered.isEmpty {
                    ContentUnavailableView {
                        Label("Scanning", systemImage: "dot.radiowaves.left.and.right")
                    } description: {
                        Text("Check that the BMS Bluetooth module is powered and that no other app is connected to it.")
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(connection.discovered) { device in
                                DeviceCard(device: device,
                                           name: connection.displayName(for: device)) {
                                    open(device)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gear") { showingSettings = true }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if connection.status == .scanning {
                        ProgressView()
                    }
                }
            }
            .refreshable { connection.startScanning() }
            .navigationDestination(item: $opened) { device in
                DeviceTabsView(deviceName: connection.displayName(for: device))
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack { AppSettingsView() }
            }
            .onChange(of: opened) { _, value in
                if value == nil { connection.close() }
            }
            .onChange(of: appSettings.showDemoDevice, initial: true) { _, show in
                connection.setShowDemoDevice(show)
            }
            .onChange(of: connection.discovered) { _, _ in
                autoConnectIfNeeded()
            }
        }
    }

    private func open(_ device: DiscoveredBMS) {
        connection.open(device)
        opened = device
    }

    /// Opens the device the user marked for auto-connect, once per launch.
    private func autoConnectIfNeeded() {
        guard !hasAutoConnected, opened == nil,
              let target = connection.autoConnectTarget else { return }
        hasAutoConnected = true
        open(target)
    }

    private var unavailableMessage: String? {
        switch connection.status {
        case .bluetoothOff:
            return "Bluetooth is turned off."
        case .unauthorized:
            return "SBU2 is not allowed to use Bluetooth. Enable access in Settings."
        case .unsupported:
            return "This device does not support Bluetooth LE."
        default:
            return nil
        }
    }
}

private struct DeviceCard: View {
    let device: DiscoveredBMS
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: device.isDemo ? "wand.and.sparkles" : "dot.radiowaves.left.and.right")
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    if let rssi = device.rssi {
                        Text("\(rssi) dBm")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(name)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(device.isDemo ? "Simulated values" : device.id)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Label("Connect", systemImage: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .labelStyle(.titleOnly)
                    .foregroundStyle(Color.accentColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 128)
            .padding(14)
        }
        .buttonStyle(.plain)
        .modifier(CardSurfaceModifier())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
        .accessibilityHint("Opens this device")
    }
}

private struct CardSurfaceModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(in: .rect(cornerRadius: 22))
        } else {
            content.background(.ultraThinMaterial,
                               in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}
