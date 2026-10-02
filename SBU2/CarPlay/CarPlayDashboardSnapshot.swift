import Foundation

/// Plain data lets the CarPlay UI update existing rows without rebuilding its
/// templates every second, and lets freshness be tested without a car display.
struct CarPlayDashboardSnapshot: Equatable {
    struct Row: Equatable {
        let title: String
        let detail: String
        let symbol: String
    }

    let rows: [Row]

    init(deviceName: String, status: BMSConnection.Status, isDemo: Bool,
         isReconnecting: Bool, hasReading: Bool, lastBasicInfoAt: Date?,
         info: BasicInfo, remainingHours: Double?, capacityUnit: CapacityUnit,
         cellNominalMillivolts: Int, lastError: String?, now: Date) {
        let state = OverviewConnectionState(status: status, isDemo: isDemo,
                                            isReconnecting: isReconnecting,
                                            hasReading: hasReading,
                                            lastBasicInfoAt: lastBasicInfoAt, now: now)
        let fresh = (isDemo || status.isConnected) && hasReading
            && BMSConnection.readingIsFresh(lastBasicInfoAt: lastBasicInfoAt, now: now)
        let statusText: String
        switch state {
        case .connecting: statusText = "Connecting…"
        case .reconnecting: statusText = "Reconnecting…"
        case .waitingForReading: statusText = "Waiting for BMS readings…"
        case .live: statusText = "Live data"
        case .outdated: statusText = "Data outdated"
        case .disconnected: statusText = "Disconnected"
        case .bluetoothOff: statusText = "Bluetooth is turned off"
        case .unauthorized: statusText = "Bluetooth access denied"
        case .unsupported: statusText = "Bluetooth LE unavailable"
        case .simulated: statusText = "Simulated values"
        }
        let alerts = info.protections.sorted { $0.rawValue < $1.rawValue }
            .map(\.label).joined(separator: ", ")
        let temperature = info.temperatures.max().map { info.temperatureText($0) } ?? "—"
        let time = remainingHours.flatMap { $0.isFinite && $0 >= 0 ? $0.asRemainingTime : nil } ?? "—"
        rows = [
            Row(title: deviceName, detail: lastError.map { statusText + " · " + $0 } ?? statusText,
                symbol: state.symbol),
            Row(title: "State of charge", detail: fresh ? info.stateOfChargeText : "—", symbol: "battery.100percent"),
            Row(title: "Alerts", detail: fresh ? (alerts.isEmpty ? "No active protections" : alerts) : "—",
                symbol: "exclamationmark.triangle"),
            Row(title: "Voltage", detail: fresh ? info.voltageText : "—", symbol: "bolt"),
            Row(title: "Current", detail: fresh ? info.currentText : "—", symbol: "arrow.left.arrow.right"),
            Row(title: "Power", detail: fresh ? info.powerText : "—", symbol: "bolt.fill"),
            Row(title: "Capacity", detail: fresh ? info.capacityText(unit: capacityUnit,
                cellNominalMillivolts: cellNominalMillivolts) : "—", symbol: "battery.100percent"),
            Row(title: "Highest temperature", detail: fresh ? temperature : "—", symbol: "thermometer.medium"),
            Row(title: info.current > 0 ? "Time to full" : "Remaining time",
                detail: fresh ? time : "—", symbol: "clock")
        ]
    }
}
