import SwiftUI

struct WatchDashboardView: View {
    @Environment(BMSConnection.self) private var connection

    let device: DiscoveredBMS

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                connectionState

                if connection.hasReading {
                    reading
                    NavigationLink(value: WatchRoute.cells) {
                        Label("Cells", systemImage: "square.grid.3x3")
                    }
                    NavigationLink(value: WatchRoute.details) {
                        Label("Details", systemImage: "list.bullet")
                    }
                    if connection.supportsMOSControl {
                        NavigationLink(value: WatchRoute.mos) {
                            Label("MOSFET controls", systemImage: "power")
                        }
                    }
                } else if connection.status.isConnected {
                    ProgressView("Reading BMS…")
                } else if case .connecting = connection.status {
                    ProgressView("Connecting…")
                }

                if !device.isDemo,
                   !connection.status.isConnected,
                   connection.lastError != nil {
                    Button("Retry connection") {
                        connection.open(device)
                    }
                }

                if let error = connection.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle(connection.displayName(for: device))
    }

    private var connectionState: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connection.status.isConnected ? .green : .orange)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            if let lastUpdate = connection.lastUpdate {
                Text(lastUpdate, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: String {
        switch connection.status {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .scanning, .idle: "Disconnected"
        case .bluetoothOff: "Bluetooth off"
        case .unauthorized: "Bluetooth denied"
        case .unsupported: "Bluetooth unavailable"
        }
    }

    private var reading: some View {
        let info = connection.info
        return VStack(spacing: 10) {
            Gauge(value: Double(info.stateOfCharge), in: 0...100) {
                Text("Charge")
            } currentValueLabel: {
                Text("\(info.stateOfCharge)%")
                    .font(.system(.title, design: .rounded).bold())
            }
            .gaugeStyle(.accessoryCircular)
            .tint(info.stateOfCharge <= 20 ? .orange : .green)
            .accessibilityLabel("State of charge")
            .accessibilityValue("\(info.stateOfCharge) percent")

            HStack(spacing: 8) {
                metric(info.voltageText, caption: "Voltage")
                metric(info.currentText, caption: "Current")
            }
            metric(info.powerText, caption: "Power")

            if let remaining = connection.remainingHours {
                Text("Estimated: \(remaining.asRemainingTime)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !info.protections.isEmpty {
                Label("\(info.protections.count) active alert(s)", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func metric(_ value: String, caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

}
