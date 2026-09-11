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

    @Test("A long string of cells opens on the figures, a short one on the bars")
    func automaticCellVoltageStyle() {
        var settings = DeviceSettings()
        // Nothing chosen: the pack's own length decides, on either side of twenty.
        #expect(settings.cellVoltageStyle(cellCount: 4) == .bars)
        #expect(settings.cellVoltageStyle(cellCount: 20) == .bars)
        #expect(settings.cellVoltageStyle(cellCount: 21) == .compact)

        // Chosen: the choice holds however many cells there are.
        settings.storedCellVoltageStyle = .aesthetic
        #expect(settings.cellVoltageStyle(cellCount: 4) == .aesthetic)
        #expect(settings.cellVoltageStyle(cellCount: 24) == .aesthetic)
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
}
