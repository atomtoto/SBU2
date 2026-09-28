import SwiftUI

enum WatchRoute: Hashable {
    case device(DiscoveredBMS)
    case cells
    case details
    case mos
}

struct WatchDeviceListView: View {
    @Environment(BMSConnection.self) private var connection
    @State private var path: [WatchRoute] = []

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
                    NavigationLink(value: WatchRoute.device(device)) {
                        HStack {
                            Image(systemName: device.isDemo ? "wand.and.sparkles" : "battery.100percent")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(connection.displayName(for: device))
                                    .lineLimit(1)
                                Text(device.isDemo ? "Demo" : device.protocolID.rawValue.uppercased())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Batteries")
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
