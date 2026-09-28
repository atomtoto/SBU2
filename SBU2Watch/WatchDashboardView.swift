import SwiftUI

struct WatchDashboardView: View {
    @Environment(BMSConnection.self) private var connection

    let device: DiscoveredBMS

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let now = Date.now
            ScrollView {
                VStack(spacing: 14) {
                    connectionState(at: now)

                    if connection.hasReading {
                        reading(isFresh: connection.hasFreshReading(at: now))

                        if !connection.hasFreshReading(at: now) {
                            Label("Waiting for fresh readings", systemImage: "arrow.clockwise")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

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
                .padding(.horizontal, 4)
            }
        }
        .navigationTitle(connection.displayName(for: device))
    }

    private func connectionState(at now: Date) -> some View {
        let isFresh = connection.hasFreshReading(at: now)
        let isStale = connection.hasReading && !isFresh
        return HStack(spacing: 6) {
            Circle()
                .fill(isStale ? .orange : (isFresh || connection.status.isConnected) ? .green : .secondary)
                .frame(width: 7, height: 7)
            Text(isStale ? "Data outdated" : statusText)
                .font(.caption)
                .foregroundStyle(isStale ? .orange : .secondary)
            Spacer(minLength: 4)
            if let lastBasicInfoAt = connection.lastBasicInfoAt {
                Text(ageText(since: lastBasicInfoAt, at: now))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isStale ? .orange : .secondary)
            }
        }
    }

    private var statusText: String {
        if connection.isDemoOpen { return "Demo live" }
        switch connection.status {
        case .connected: return "Live"
        case .connecting: return "Connecting"
        case .scanning, .idle: return "Disconnected"
        case .bluetoothOff: return "Bluetooth off"
        case .unauthorized: return "Bluetooth denied"
        case .unsupported: return "Bluetooth unavailable"
        }
    }

    private func ageText(since reading: Date, at now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(reading)))
        if seconds < 2 { return "now" }
        if seconds < 60 { return "\(seconds)s ago" }
        return "\(seconds / 60)m ago"
    }

    private func reading(isFresh: Bool) -> some View {
        let info = connection.info
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                chargeRing(info.stateOfCharge)

                VStack(alignment: .leading, spacing: 4) {
                    Label(flowText(for: info.current), systemImage: flowSymbol(for: info.current))
                        .font(.caption2)
                        .foregroundStyle(info.current > 0.25 ? .green : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(info.powerText)
                        .font(.system(.title3, design: .rounded).bold())
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("Power")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                metric(info.voltageText, caption: "Voltage")
                metric(info.currentText, caption: "Current")
            }

            if let remaining = connection.remainingHours {
                Label("About \(remaining.asRemainingTime) remaining", systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !info.protections.isEmpty {
                Label("\(info.protections.count) active alert(s)", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .opacity(isFresh ? 1 : 0.55)
    }

    private func chargeRing(_ percentage: Int) -> some View {
        let progress = min(max(Double(percentage) / 100, 0), 1)
        let tint: Color = percentage <= 20 ? .orange : .green
        return ZStack {
            Circle()
                .stroke(.white.opacity(0.13), lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(percentage)%")
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .frame(width: 84, height: 84)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("State of charge")
        .accessibilityValue("\(percentage) percent")
    }

    private func metric(_ value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.headline, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private func flowText(for current: Double) -> String {
        if current > 0.25 { return "Charging" }
        if current < -0.25 { return "Discharging" }
        return "Idle"
    }

    private func flowSymbol(for current: Double) -> String {
        if current > 0.25 { return "bolt.fill" }
        if current < -0.25 { return "arrow.down.right" }
        return "minus"
    }
}
