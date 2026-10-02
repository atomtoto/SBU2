import Foundation
import Testing
@testable import SBU2

@Suite("Overview connection status")
struct OverviewConnectionStateTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    @Test("Connecting, waiting for measurements and reconnecting are distinct")
    func waitingStates() {
        #expect(state(status: .connecting("BMS"), hasReading: false) == .connecting)
        #expect(state(status: .connected("BMS"), hasReading: false) == .waitingForReading)
        #expect(state(status: .connecting("BMS"), isReconnecting: true,
                      hasReading: false) == .reconnecting)
        // GATT is ready after a retry, but no new pack reading has arrived yet.
        #expect(state(status: .connected("BMS"), isReconnecting: true,
                      hasReading: false) == .reconnecting)
    }

    @Test("Measurements become outdated at the same threshold as MOSFET controls")
    func freshnessBoundary() {
        #expect(state(lastBasicInfoAt: now) == .live)
        #expect(state(lastBasicInfoAt: now.addingTimeInterval(-BMSConnection.readingStaleAfter)) == .live)
        #expect(state(lastBasicInfoAt: now.addingTimeInterval(-BMSConnection.readingStaleAfter - 0.1)) == .outdated)
    }

    @Test("A missing timestamp or backwards clock cannot produce a live label")
    func invalidTimestamp() {
        #expect(state(lastBasicInfoAt: nil) == .outdated)
        #expect(state(lastBasicInfoAt: now.addingTimeInterval(1)) == .outdated)
    }

    @Test("An unavailable connection takes precedence over a recent reading",
          arguments: [
            (BMSConnection.Status.idle, OverviewConnectionState.disconnected),
            (.scanning, .disconnected),
            (.bluetoothOff, .bluetoothOff),
            (.unauthorized, .unauthorized),
            (.unsupported, .unsupported)
          ])
    func unavailable(status: BMSConnection.Status, expected: OverviewConnectionState) {
        #expect(state(status: status, lastBasicInfoAt: now) == expected)
    }

    @Test("The demo stays explicitly simulated even without Bluetooth")
    func demoWithoutBluetooth() {
        let value = OverviewConnectionState(status: .bluetoothOff, isDemo: true,
                                            isReconnecting: false, hasReading: true,
                                            lastBasicInfoAt: now, now: now)
        #expect(value == .simulated)
    }

    private func state(status: BMSConnection.Status = .connected("BMS"),
                       isReconnecting: Bool = false, hasReading: Bool = true,
                       lastBasicInfoAt: Date? = nil) -> OverviewConnectionState {
        OverviewConnectionState(status: status, isDemo: false,
                                isReconnecting: isReconnecting, hasReading: hasReading,
                                lastBasicInfoAt: lastBasicInfoAt, now: now)
    }
}
