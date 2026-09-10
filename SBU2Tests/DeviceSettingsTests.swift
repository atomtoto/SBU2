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

        // Both settings added later read as the behaviour that came before them.
        #expect(settings.protocolID == nil)
        #expect(settings.refillTarget == .chargeLimit)
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
