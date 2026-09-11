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
    @State private var hasAutoConnected = false
    /// The device whose icon is being chosen.
    @State private var customising: DiscoveredBMS?
    /// Icons picked in this session. The store behind them is plain `UserDefaults`,
    /// which nothing observes, so a pick is held here too in order to reach the card
    /// it was made on straight away.
    @State private var pickedIcons: [String: DeviceIcon?] = [:]

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
                                           name: connection.displayName(for: device),
                                           icon: icon(for: device)) {
                                    open(device)
                                } onCustomise: {
                                    customising = device
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
                    // Pushed onto the stack rather than presented as a sheet, so the
                    // settings slide in from the edge the way they did in SBU — and so
                    // "About this app" drills down in the same stack instead of
                    // stacking a second navigation inside a card.
                    NavigationLink {
                        AppSettingsView()
                    } label: {
                        Label("Settings", systemImage: "gear")
                            .labelStyle(.iconOnly)
                    }
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
            .sheet(item: $customising) { device in
                DeviceIconPicker(deviceName: connection.displayName(for: device),
                                 current: storedIcon(for: device),
                                 defaultIcon: .standard(isDemo: device.isDemo)) { picked in
                    setIcon(picked, for: device)
                }
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

    // MARK: - Icons

    /// What this device draws for itself, honouring a pick made a moment ago before
    /// falling back to what is on disk.
    private func icon(for device: DiscoveredBMS) -> DeviceIcon {
        if let picked = pickedIcons[device.id] {
            return picked ?? .standard(isDemo: device.isDemo)
        }
        return DeviceSettingsStore.load(device.id).icon(isDemo: device.isDemo)
    }

    /// The choice itself rather than the resolved icon: `nil` means "still on the
    /// default", which is what the picker needs to know to offer putting it back.
    private func storedIcon(for device: DiscoveredBMS) -> DeviceIcon? {
        if let picked = pickedIcons[device.id] { return picked }
        return DeviceSettingsStore.load(device.id).storedIcon
    }

    private func setIcon(_ icon: DeviceIcon?, for device: DiscoveredBMS) {
        var settings = DeviceSettingsStore.load(device.id)
        settings.storedIcon = icon
        DeviceSettingsStore.save(settings, for: device.id)
        pickedIcons.updateValue(icon, forKey: device.id)

        // The open device holds its own copy of these settings, so write it there
        // too rather than leaving the two to disagree until the next reconnection.
        if connection.openDeviceID == device.id {
            connection.settings.storedIcon = icon
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
    let icon: DeviceIcon
    let action: () -> Void
    let onCustomise: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    DeviceIconView(icon: icon)
                        .frame(width: 22, height: 22, alignment: .leading)
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
        .contextMenu {
            Button("Change Icon…", systemImage: "face.smiling", action: onCustomise)
        }
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
