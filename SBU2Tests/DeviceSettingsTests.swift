//
//  DeviceSettingsTests.swift
//  SBU2Tests
//

import Foundation
import Testing
@testable import SBU2

@Suite("Stored device settings")
struct DeviceSettingsTests {

    /// Exactly what `UserDefaults` holds for a device paired before `refillTarget`
    /// existed: every key that was current then, and none that were not.
    private let storedBeforeRefillTarget = """
    {"name":"Van","kind":"vehicle","autoConnect":true,
     "hasPassword":true,"password":"123456",
     "cellEmptyVoltage":2800,"cellNominalVoltage":3200,"cellFullVoltage":3650,
     "expectedPower":2000,"expectedRange":120,
     "showPowerDial":true,"showSpeedDial":false,"showRangeDial":true,
     "chargeLimitEnabled":true,"alwaysShowChargeLimit":false,
     "chargeLimitMode":"stateOfCharge","chargeLimitSOC":80,"chargeLimitVoltage":3.25,
     "refillLaterEnabled":true,"refillDate":0}
    """

    @Test("A device stored before a setting existed keeps everything else")
    func decodesWithoutNewerKeys() throws {
        let settings = try JSONDecoder().decode(DeviceSettings.self,
                                                from: Data(storedBeforeRefillTarget.utf8))

        // The synthesized decoder throws on a missing key even where the property
        // has a default, and `DeviceSettingsStore.load` answers a throw by handing
        // back factory settings. The password is what makes that expensive: the app
        // says outright that it cannot be recovered.
        #expect(settings.password == "123456")
        #expect(settings.hasPassword)
        #expect(settings.name == "Van")
        #expect(settings.kind == .vehicle)
        #expect(settings.chargeLimitSOC == 80)
        #expect(settings.cellFullVoltage == 3650)
        #expect(settings.refillLaterEnabled)

        // Every setting added later reads as the behaviour that came before it.
        #expect(settings.protocolID == nil)
        #expect(settings.refillTarget == .chargeLimit)
        #expect(settings.storedIcon == nil)
        #expect(settings.overviewStyle == .ring)
        #expect(settings.storedCellVoltageStyle == nil)
        #expect(settings.speedDialStyle == .ring)
        #expect(settings.speedDialMaximum == 80)
        #expect(settings.radioSpeedIndicatorStyle == .glassNeedle)
    }

    @Test("Radio dial preferences survive storage without affecting other devices")
    func radioDialRoundTrips() throws {
        var settings = DeviceSettings()
        settings.speedDialStyle = .radio
        settings.speedDialMaximum = 140
        settings.radioSpeedIndicatorStyle = .growingBar
        let decoded = try JSONDecoder().decode(DeviceSettings.self,
                                               from: JSONEncoder().encode(settings))
        #expect(decoded.speedDialStyle == .radio)
        #expect(decoded.speedDialMaximum == 140)
        #expect(decoded.radioSpeedIndicatorStyle == .growingBar)
        #expect(DeviceSettings().speedDialStyle == .ring)

        // Invalid stored scales must not produce division by zero or an empty ruler.
        settings.storedSpeedDialMaximum = 0
        #expect(settings.speedDialMaximum == 20)
        settings.storedSpeedDialMaximum = 500
        #expect(settings.speedDialMaximum == 300)
    }

    @Test("Every kind of icon survives being written and read back")
    func iconRoundTrips() throws {
        for icon: DeviceIcon in [.symbol("car.fill"), .emoji("🚐"), .glyph(Data([0x1, 0x2, 0x3]))] {
            var settings = DeviceSettings()
            settings.storedIcon = icon
            let decoded = try JSONDecoder().decode(DeviceSettings.self,
                                                   from: JSONEncoder().encode(settings))
            #expect(decoded.storedIcon == icon)
        }
    }

    @Test("The first reading fixes the style for good, from the pack's own length")
    func automaticCellVoltageStyleResolvesOnce() {
        var shortPack = DeviceSettings()
        // Nothing chosen yet: the first reading sets the style from the cell count,
        // on either side of twenty.
        shortPack.resolveAutomaticStyles(cellCount: 4)
        #expect(shortPack.cellVoltageStyle == .bars)

        var longPack = DeviceSettings()
        longPack.resolveAutomaticStyles(cellCount: 24)
        #expect(longPack.cellVoltageStyle == .compact)

        // Resolved is resolved: a later reading does not revisit it.
        longPack.resolveAutomaticStyles(cellCount: 4)
        #expect(longPack.cellVoltageStyle == .compact)

        // Chosen before any reading: the choice holds rather than being overwritten.
        var chosen = DeviceSettings()
        chosen.cellVoltageStyle = .aesthetic
        chosen.resolveAutomaticStyles(cellCount: 24)
        #expect(chosen.cellVoltageStyle == .aesthetic)
    }

    @Test("Styles are per device, so one pack's choice is not another's")
    func stylesAreNotShared() throws {
        var van = DeviceSettings()
        van.overviewStyle = .bars
        van.storedCellVoltageStyle = .compact

        let shed = DeviceSettings()
        #expect(shed.overviewStyle == .ring)
        #expect(shed.storedCellVoltageStyle == nil)

        let decoded = try JSONDecoder().decode(DeviceSettings.self,
                                               from: JSONEncoder().encode(van))
        #expect(decoded.overviewStyle == .bars)
        #expect(decoded.storedCellVoltageStyle == .compact)
    }

    @Test("The chosen refill target survives being written and read back")
    func refillTargetRoundTrips() throws {
        var settings = DeviceSettings()
        #expect(settings.refillTarget == .chargeLimit)

        settings.refillTarget = .full
        let decoded = try JSONDecoder().decode(DeviceSettings.self,
                                               from: JSONEncoder().encode(settings))
        #expect(decoded.refillTarget == .full)
    }

    @Test("Forgetting a device drops everything it had stored")
    func forgetPurgesTheStore() {
        let id = "FORGET-ME-\(UUID().uuidString)"
        var settings = DeviceSettings()
        settings.name = "Van"
        settings.autoConnect = true
        settings.storedIcon = .emoji("🚐")
        DeviceSettingsStore.save(settings, for: id)
        defer { DeviceSettingsStore.forget(id) }

        #expect(DeviceSettingsStore.load(id).name == "Van")

        DeviceSettingsStore.forget(id)

        // What loads next is the factory device again, as if never seen.
        let reloaded = DeviceSettingsStore.load(id)
        #expect(reloaded.name.isEmpty)
        #expect(!reloaded.autoConnect)
        #expect(reloaded.storedIcon == nil)
    }

}

@Suite("Stored app settings")
struct AppSettingsTests {

    /// Exactly what `UserDefaults` held before the high-contrast choice existed: every
    /// key that was current then, and none that were not.
    private let storedBeforeHighContrast = """
    {"showDemoDevice":false,"capacityUnit":"wattHours","keepScreenAwake":true,
     "appearance":"dark","showMOSFETWarning":false}
    """

    @Test("Settings stored before the newest one keep everything else")
    func decodesWithoutNewerKeys() throws {
        // The whole point of the optional: the synthesized decoder throws on a missing
        // key even where the property has a default, and a throw here is answered by
        // keeping the factory settings — which would cost everyone their theme and
        // their units the first time they opened this version.
        let stored = try JSONDecoder().decode(AppSettings.Snapshot.self,
                                              from: Data(storedBeforeHighContrast.utf8))
        #expect(stored.showDemoDevice == false)
        #expect(stored.capacityUnit == .wattHours)
        #expect(stored.keepScreenAwake)
        #expect(stored.appearance == .dark)
        #expect(stored.showMOSFETWarning == false)
        // Absent, which the app reads as off.
        #expect(stored.highContrastFigures == nil)
    }

    @Test("The glass is what the figures wear unless someone says otherwise")
    func highContrastIsOptIn() throws {
        #expect(AppSettings.Snapshot().highContrastFigures == nil)

        var asked = AppSettings.Snapshot()
        asked.highContrastFigures = true
        let decoded = try JSONDecoder().decode(AppSettings.Snapshot.self,
                                               from: JSONEncoder().encode(asked))
        #expect(decoded.highContrastFigures == true)
    }
}
