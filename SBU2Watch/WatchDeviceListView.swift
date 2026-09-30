import SwiftUI

enum WatchRoute: Hashable {
    case device(DiscoveredBMS)
    case cells
    case details
    case mos
}

struct WatchDeviceListView: View {
    @Environment(BMSConnection.self) private var connection
    @Environment(ICloudSettingsSync.self) private var iCloudSync
    @State private var path: [WatchRoute] = []
    @State private var syncingDevice: DiscoveredBMS?
    @State private var showingICloudSettings = false

    private var devices: [DiscoveredBMS] {
        connection.discovered.sorted {
            if $0.isDemo != $1.isDemo { return $0.isDemo }
            return ($0.rssi ?? -100) > ($1.rssi ?? -100)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let message = statusMessage {
                    Label(message, systemImage: statusSymbol)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(devices) { device in
                    HStack(spacing: 8) {
                        NavigationLink(value: WatchRoute.device(device)) {
                            HStack {
                                deviceIcon(for: device)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(displayName(for: device))
                                        .lineLimit(1)
                                    Text(device.isDemo ? "Demo" : device.protocolID.rawValue.uppercased())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if !device.isDemo {
                            Button("iCloud Profile", systemImage: iCloudSync.profileID(for: device.id) == nil ? "icloud" : "icloud.fill") {
                                syncingDevice = device
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 32, height: 44)
                            .contentShape(Rectangle())
                            .accessibilityLabel("iCloud profile for \(displayName(for: device))")
                        }
                    }
                }
            }
            .navigationTitle("Batteries")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("iCloud Settings", systemImage: "icloud") {
                        showingICloudSettings = true
                    }
                }
            }
            .sheet(isPresented: $showingICloudSettings) {
                NavigationStack {
                    WatchICloudSettingsView()
                }
            }
            .sheet(item: $syncingDevice) { device in
                NavigationStack {
                    WatchDeviceSyncView(device: device)
                }
            }
            .navigationDestination(for: WatchRoute.self) { route in
                switch route {
                case .device(let device): WatchDashboardView(device: device)
                case .cells: WatchCellsView()
                case .details: WatchDetailsView()
                case .mos: WatchMOSView()
                }
            }
            .onAppear {
                if path.isEmpty { connection.startScanning() }
            }
            .onChange(of: path) { oldPath, newPath in
                guard oldPath.first != newPath.first else { return }
                if case .device(let device) = newPath.first {
                    connection.open(device)
                } else {
                    connection.close()
                }
            }
        }
    }

    private func displayName(for device: DiscoveredBMS) -> String {
        _ = iCloudSync.revision
        return connection.displayName(for: device)
    }

    @ViewBuilder
    private func deviceIcon(for device: DiscoveredBMS) -> some View {
        let _ = iCloudSync.revision
        switch DeviceSettingsStore.load(device.id).storedIcon {
        case .symbol(let symbol):
            Image(systemName: symbol).foregroundStyle(.green)
        case .emoji(let emoji):
            Text(emoji)
        case .glyph, .none:
            Image(systemName: device.isDemo ? "wand.and.sparkles" : "battery.100percent")
                .foregroundStyle(.green)
        }
    }

    private var statusMessage: String? {
        switch connection.status {
        case .bluetoothOff: "Turn on Bluetooth to find a BMS."
        case .unauthorized: "Allow Bluetooth access in Settings."
        case .unsupported: "Bluetooth is unavailable."
        case .idle, .scanning: devices.contains(where: { !$0.isDemo }) ? nil : "Looking for nearby BMS devices…"
        case .connecting, .connected: nil
        }
    }

    private var statusSymbol: String {
        switch connection.status {
        case .bluetoothOff, .unauthorized, .unsupported: "exclamationmark.triangle"
        default: "dot.radiowaves.left.and.right"
        }
    }
}

private struct WatchICloudSettingsView: View {
    @Environment(ICloudSettingsSync.self) private var iCloudSync

    var body: some View {
        Form {
            Toggle("Sync with iCloud", isOn: Binding(
                get: { iCloudSync.isEnabled },
                set: { iCloudSync.setEnabled($0) }
            ))
            Text(iCloudSync.statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Sync Now") { iCloudSync.synchronize() }
                .disabled(!iCloudSync.isEnabled)
            Text("Shares app preferences and BMS profiles with your devices using the same iCloud account. Tap the cloud beside a battery to link its profile. Passwords, auto-connect and MOSFET confirmations stay on this watch.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .navigationTitle("iCloud")
    }
}

private struct WatchDeviceSyncView: View {
    @Environment(BMSConnection.self) private var connection
    @Environment(ICloudSettingsSync.self) private var iCloudSync
    @State private var pendingProfile: SyncedDeviceProfile?
    @State private var profileUnavailable = false

    let device: DiscoveredBMS

    private var currentProfileID: String? {
        iCloudSync.profileID(for: device.id)
    }

    var body: some View {
        List {
            Text(connection.displayName(for: device))
                .font(.headline)
            Section {
                if let profile = iCloudSync.profiles.first(where: { $0.id == currentProfileID }) {
                    LabeledContent("Profile", value: profile.label)
                    Button("Stop Sharing on This Watch") {
                        iCloudSync.unlinkDevice(device.id)
                    }
                } else {
                    Button("Share This BMS") {
                        if connection.openDeviceID == device.id {
                            connection.saveSettings()
                        } else {
                            // This sheet can be opened before connecting. Keep the
                            // detected protocol so the new profile stays in its family.
                            var settings = DeviceSettingsStore.load(device.id)
                            settings.protocolID = device.protocolID
                            DeviceSettingsStore.save(settings, for: device.id)
                        }
                        iCloudSync.shareDevice(device.id, fallbackName: connection.displayName(for: device))
                    }
                    .disabled(!iCloudSync.isEnabled)
                }

                Text(iCloudSync.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Use one profile for the same physical BMS on all your devices. Stopping sharing keeps its current settings on this watch.")
            }

            Section {
                if iCloudSync.availableProfiles(for: device.protocolID).isEmpty {
                    Text("No compatible profiles yet. Create one on your other device, then sync iCloud.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(iCloudSync.availableProfiles(for: device.protocolID)) { profile in
                    Button {
                        pendingProfile = profile
                    } label: {
                        HStack {
                            Text(profile.label)
                            Spacer()
                            if profile.id == currentProfileID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(!iCloudSync.isEnabled || profile.id == currentProfileID)
                }
            } header: {
                Text("Link a Profile")
            } footer: {
                Text(iCloudSync.isEnabled
                     ? "Linking replaces this watch's name, icon and shared settings. Your password and auto-connect choice stay on this watch."
                     : "Enable iCloud sync to share or link this BMS.")
            }
        }
        .navigationTitle("iCloud Profile")
        .confirmationDialog("Use “\(pendingProfile?.label ?? "this profile")”?",
                            isPresented: Binding(
                                get: { pendingProfile != nil },
                                set: { if !$0 { pendingProfile = nil } }
                            ),
                            titleVisibility: .visible) {
            if let profile = pendingProfile {
                Button("Use Profile") {
                    if !iCloudSync.linkDevice(device.id, to: profile.id) {
                        profileUnavailable = true
                    }
                    pendingProfile = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingProfile = nil }
        } message: {
            Text("This replaces the name, icon and shared settings saved for this BMS on this watch.")
        }
        .alert("Profile unavailable", isPresented: $profileUnavailable) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Refresh iCloud and try again.")
        }
    }
}
