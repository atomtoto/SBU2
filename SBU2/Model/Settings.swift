//
//  Settings.swift
//  SBU2
//

import Foundation
import Observation

// MARK: - App-wide settings

enum Appearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum CapacityUnit: String, Codable, CaseIterable, Identifiable {
    case ampereHours, wattHours

    var id: Self { self }

    var label: String {
        switch self {
        case .ampereHours: return "Ah"
        case .wattHours: return "kWh"
        }
    }
}

/// Preferences shared by the whole app.
///
/// Persistence is explicit rather than driven by `didSet`: the `@Observable` macro
/// rewrites stored properties into computed ones, so property observers on them are
/// not a reliable place to hang side effects.
@Observable
final class AppSettings {

    private static let key = "app.settings"

    var showDemoDevice = true
    var capacityUnit: CapacityUnit = .ampereHours
    var keepScreenAwake = false
    var appearance: Appearance = .system

    struct Snapshot: Codable, Equatable {
        var showDemoDevice = true
        var capacityUnit: CapacityUnit = .ampereHours
        var keepScreenAwake = false
        var appearance: Appearance = .system
    }

    /// Equatable view of the settings, so a single `onChange` can drive persistence.
    var snapshot: Snapshot {
        Snapshot(showDemoDevice: showDemoDevice,
                 capacityUnit: capacityUnit,
                 keepScreenAwake: keepScreenAwake,
                 appearance: appearance)
    }

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let stored = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        showDemoDevice = stored.showDemoDevice
        capacityUnit = stored.capacityUnit
        keepScreenAwake = stored.keepScreenAwake
        appearance = stored.appearance
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

// MARK: - Per-device settings

enum DeviceKind: String, Codable, CaseIterable, Identifiable {
    case classic, vehicle, storage

    var id: Self { self }

    var label: String {
        switch self {
        case .classic: return "Classic"
        case .vehicle: return "Vehicle"
        case .storage: return "Stationary storage"
        }
    }
}

/// Some Liontron packs reject every write until their hardware password is entered.
/// The BMS answers `0x80`, which the app uses to lock the MOSFET buttons rather than
/// letting the user issue commands that silently fail.
enum LiontronMode: String, Codable, CaseIterable, Identifiable {
    case autoDisabled, autoEnabled, disabled

    var id: Self { self }

    var label: String {
        switch self {
        case .autoDisabled: return "Auto (off)"
        case .autoEnabled: return "Auto (on)"
        case .disabled: return "Disabled"
        }
    }
}

enum ChargeLimitMode: String, Codable, CaseIterable, Identifiable {
    case stateOfCharge, cellVoltage

    var id: Self { self }

    var label: String {
        switch self {
        case .stateOfCharge: return "SOC (%)"
        case .cellVoltage: return "Voltage"
        }
    }
}

/// Everything the app remembers about one BMS, keyed by its peripheral identifier.
struct DeviceSettings: Codable, Equatable {
    var name = ""
    var kind: DeviceKind = .classic
    var autoConnect = false

    var hasPassword = false
    var password = "000000"

    var cellEmptyVoltage = 3000      // mV
    var cellNominalVoltage = 3700    // mV
    var cellFullVoltage = 4200       // mV

    var expectedPower = 1000         // W, calibrates the power dial
    var expectedRange = 65           // km or mi, calibrates the range dial

    var showPowerDial = true
    var showSpeedDial = true
    var showRangeDial = true

    var liontronMode: LiontronMode = .autoDisabled

    var chargeLimitEnabled = false
    var alwaysShowChargeLimit = false
    var chargeLimitMode: ChargeLimitMode = .stateOfCharge
    var chargeLimitSOC: Double = 80
    var chargeLimitVoltage: Double = 3.25
    var refillLaterEnabled = false
    var refillDate: Date = .now
}

/// Loads and stores `DeviceSettings` per peripheral in `UserDefaults`.
enum DeviceSettingsStore {

    private static func key(for id: String) -> String { "device.settings.\(id)" }

    static func load(_ id: String) -> DeviceSettings {
        guard let data = UserDefaults.standard.data(forKey: key(for: id)),
              let settings = try? JSONDecoder().decode(DeviceSettings.self, from: data)
        else { return DeviceSettings() }
        return settings
    }

    static func save(_ settings: DeviceSettings, for id: String) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key(for: id))
    }
}
