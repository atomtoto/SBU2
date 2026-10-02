import Foundation
import Testing
@testable import SBU2
#if os(iOS) && !targetEnvironment(macCatalyst)
import CarPlay
#endif

@Suite("CarPlay battery readings")
struct CarPlayDashboardTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    #if os(iOS) && !targetEnvironment(macCatalyst)
    @Test("CarPlay can invoke both scene lifecycle callbacks")
    @MainActor
    func sceneCallbacks() {
        let delegate = CarPlaySceneDelegate()
        #expect(delegate.responds(to: #selector(CPTemplateApplicationSceneDelegate.templateApplicationScene(_:didConnect:))))
        #expect(delegate.responds(to: #selector(CPTemplateApplicationSceneDelegate.templateApplicationScene(_:didDisconnectInterfaceController:))))
    }

    @Test("The built app declares the CarPlay scene and background Bluetooth")
    func sceneConfiguration() throws {
        let manifest = try #require(Bundle.main.infoDictionary?["UIApplicationSceneManifest"] as? [String: Any])
        let configurations = try #require(manifest["UISceneConfigurations"] as? [String: Any])
        let scenes = try #require(configurations["CPTemplateApplicationSceneSessionRoleApplication"] as? [[String: Any]])
        #expect(scenes.first?["UISceneClassName"] as? String == "CPTemplateApplicationScene")
        #expect(scenes.first?["UISceneDelegateClassName"] as? String == "SBU2.CarPlaySceneDelegate")
        let modes = try #require(Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String])
        #expect(modes.contains("bluetooth-central"))
    }
    #endif

    @Test("Fresh readings expose pack values and ordered protections")
    func freshReading() {
        let value = snapshot()
        #expect(value.rows[0].detail == "Live data")
        #expect(value.rows[1].detail == "65 %")
        #expect(value.rows[2].detail == "Cell overvoltage, Short circuit detected")
        #expect(value.rows.first { $0.title == "Voltage" }?.detail == info.voltageText)
        #expect(value.rows.last?.title == "Remaining time")
        #expect(value.rows.last?.detail == "2 h 30 min")
    }

    @Test("Stale, unavailable and missing readings never appear as current values")
    func unavailableReadings() {
        for value in [snapshot(age: 5.1), snapshot(hasReading: false),
                      snapshot(status: .bluetoothOff), snapshot(status: .idle),
                      snapshot(age: -1), snapshot(timestamp: false)] {
            #expect(value.rows.dropFirst().allSatisfy { $0.detail == "—" })
        }
        #expect(snapshot(age: 5).rows[1].detail == "65 %")
        #expect(snapshot(age: 5.1).rows[0].detail == "Data outdated")
    }

    @Test("Connection retries and hardware failures remain visible")
    func connectionErrors() {
        #expect(snapshot(status: .connecting("BMS"), hasReading: false,
                         isReconnecting: true).rows[0].detail == "Reconnecting…")
        #expect(snapshot(hasReading: false).rows[0].detail == "Waiting for BMS readings…")
        #expect(snapshot(lastError: "Could not connect.").rows[0].detail.contains("Could not connect."))
    }

    @Test("Demo values remain labelled and cannot bypass timestamp freshness")
    func demo() {
        let value = snapshot(status: .bluetoothOff, isDemo: true)
        #expect(value.rows[0].detail == "Simulated values")
        #expect(value.rows[1].detail == "65 %")
        #expect(snapshot(isDemo: true, age: 6).rows[1].detail == "—")
    }

    @Test("Missing estimates and temperatures use placeholders")
    func missingOptionalValues() {
        var reading = info
        reading.current = 1
        reading.temperatures = []
        reading.protections = []
        let value = snapshot(reading: reading, remainingHours: .infinity)
        #expect(value.rows[2].detail == "No active protections")
        #expect(value.rows.first { $0.title == "Highest temperature" }?.detail == "—")
        #expect(value.rows.last?.title == "Time to full")
        #expect(value.rows.last?.detail == "—")
    }

    private var info: BasicInfo {
        var value = BasicInfo()
        value.packVoltage = 52
        value.current = -10
        value.stateOfCharge = 65
        value.residualCapacity = 13
        value.nominalCapacity = 20
        value.cellCount = 14
        value.temperatures = [22, 30]
        value.protections = [.shortCircuit, .cellOverVoltage]
        return value
    }

    private func snapshot(status: BMSConnection.Status = .connected("BMS"),
                          isDemo: Bool = false, age: TimeInterval = 0,
                          hasReading: Bool = true, isReconnecting: Bool = false,
                          timestamp: Bool = true, lastError: String? = nil,
                          reading: BasicInfo? = nil, remainingHours: Double? = 2.5) -> CarPlayDashboardSnapshot {
        CarPlayDashboardSnapshot(deviceName: "Battery", status: status, isDemo: isDemo,
            isReconnecting: isReconnecting, hasReading: hasReading,
            lastBasicInfoAt: timestamp ? now.addingTimeInterval(-age) : nil,
            info: reading ?? info, remainingHours: remainingHours, capacityUnit: .ampereHours,
            cellNominalMillivolts: 3_700, lastError: lastError, now: now)
    }
}
