import SwiftUI

/// Uses the basic-information timestamp, so cell notifications cannot make old
/// pack values look live. The caller refreshes this notice once a second.
struct OverviewConnectionNotice: View {
    let state: OverviewConnectionState
    let lastBasicInfoAt: Date?
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if state.isWaiting {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: state.symbol)
                    .foregroundStyle(state.tint)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(state.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(state.tint)
                if state != .simulated, let lastBasicInfoAt, lastBasicInfoAt <= now {
                    Text("Last reading \(lastBasicInfoAt, style: .relative) ago")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

enum OverviewConnectionState: Equatable {
    case connecting, reconnecting, waitingForReading, live, outdated
    case disconnected, bluetoothOff, unauthorized, unsupported, simulated

    init(status: BMSConnection.Status, isDemo: Bool, isReconnecting: Bool,
         hasReading: Bool, lastBasicInfoAt: Date?, now: Date) {
        if isDemo {
            self = .simulated
            return
        }
        switch status {
        case .connecting:
            self = isReconnecting ? .reconnecting : .connecting
        case .connected:
            if !hasReading {
                self = isReconnecting ? .reconnecting : .waitingForReading
            } else {
                self = BMSConnection.readingIsFresh(lastBasicInfoAt: lastBasicInfoAt, now: now)
                    ? .live : .outdated
            }
        case .bluetoothOff:
            self = .bluetoothOff
        case .unauthorized:
            self = .unauthorized
        case .unsupported:
            self = .unsupported
        case .idle, .scanning:
            self = .disconnected
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .connecting: "Connecting…"
        case .reconnecting: "Reconnecting…"
        case .waitingForReading: "Waiting for BMS readings…"
        case .live: "Live data"
        case .outdated: "Data outdated"
        case .disconnected: "Disconnected"
        case .bluetoothOff: "Bluetooth is turned off"
        case .unauthorized: "Bluetooth access denied"
        case .unsupported: "Bluetooth LE unavailable"
        case .simulated: "Simulated values"
        }
    }

    var isWaiting: Bool {
        self == .connecting || self == .reconnecting || self == .waitingForReading
    }

    var tint: Color {
        switch self {
        case .live: .green
        case .outdated, .disconnected, .bluetoothOff, .unauthorized, .unsupported: .orange
        default: .secondary
        }
    }

    var symbol: String {
        switch self {
        case .live: "checkmark.circle.fill"
        case .outdated: "exclamationmark.triangle.fill"
        case .simulated: "flask"
        default: "antenna.radiowaves.left.and.right.slash"
        }
    }
}
