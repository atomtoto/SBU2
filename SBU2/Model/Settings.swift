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
    /// Whether tapping a MOSFET button asks for confirmation first. Off once the
    /// user dismisses the warning with "Don't warn me again".
    var showMOSFETWarning = true

    struct Snapshot: Codable, Equatable {
        var showDemoDevice = true
        var capacityUnit: CapacityUnit = .ampereHours
        var keepScreenAwake = false
        var appearance: Appearance = .system
        var showMOSFETWarning = true
    }

    /// Equatable view of the settings, so a single `onChange` can drive persistence.
    var snapshot: Snapshot {
        Snapshot(showDemoDevice: showDemoDevice,
                 capacityUnit: capacityUnit,
                 keepScreenAwake: keepScreenAwake,
                 appearance: appearance,
                 showMOSFETWarning: showMOSFETWarning)
    }

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let stored = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        showDemoDevice = stored.showDemoDevice
        capacityUnit = stored.capacityUnit
        keepScreenAwake = stored.keepScreenAwake
        appearance = stored.appearance
        showMOSFETWarning = stored.showMOSFETWarning
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

/// What the cells are made of, which is what decides how a charge finishes.
enum CellChemistry: String, Codable, CaseIterable, Identifiable {
    /// The cobalt-oxide family — NMC, LCO — at around 4.2 V a cell.
    case lithiumIon
    /// Iron phosphate: 3.65 V a cell, and a far flatter curve on the way there.
    case lithiumIronPhosphate

    var id: Self { self }

    var label: String {
        switch self {
        case .lithiumIon: return "Li-ion"
        case .lithiumIronPhosphate: return "LFP"
        }
    }

    /// How much of the pack goes in before the charger stops holding the current
    /// steady and starts holding the voltage instead.
    ///
    /// Iron-phosphate cells sit on their plateau nearly to the top and give up only
    /// the last few percent to the taper. Cobalt-oxide cells start tapering with a
    /// quarter of the charge still to go, which is why their last bar takes so long.
    var constantVoltageOnset: Double {
        switch self {
        case .lithiumIon: return 0.75
        case .lithiumIronPhosphate: return 0.95
        }
    }

    /// A guess from the full-cell voltage already configured, for a device set up
    /// before the app thought to ask. The two families are far enough apart in the
    /// volt-and-a-half between them that the midpoint separates them cleanly.
    static func inferred(fromCellFullVoltage millivolts: Int) -> CellChemistry {
        millivolts < 3900 ? .lithiumIronPhosphate : .lithiumIon
    }
}

/// Where a scheduled refill stops.
///
/// The charge limit keeps the pack at a level it is happy sitting at. A refill is
/// what happens when that level is not what you want any more: either the pack has
/// drifted below the limit and should go back to it, or it is about to be used and
/// should go all the way up — late, so it spends as little time full as it can.
enum RefillTarget: String, Codable, CaseIterable, Identifiable {
    case chargeLimit, full

    var id: Self { self }
}

/// Everything the app remembers about one BMS, keyed by its peripheral identifier.
struct DeviceSettings: Codable, Equatable {
    var name = ""
    var kind: DeviceKind = .classic
    var autoConnect = false

    /// The BMS family this device speaks. `nil` on a device stored before the app
    /// supported more than one, and on one that has never been opened — the
    /// advertisement decides then.
    var protocolID: BMSProtocolID?

    var hasPassword = false
    var password = "000000"

    var cellEmptyVoltage = 3000      // mV
    var cellNominalVoltage = 3700    // mV
    var cellFullVoltage = 4200       // mV

    /// Optional for the same reason as `storedRefillTarget`, and read through
    /// `chemistry`.
    var storedChemistry: CellChemistry?

    /// Falls back to whatever the configured full-cell voltage implies, so a device
    /// paired before the app asked still estimates against the right curve without
    /// anyone having to go and tell it.
    var chemistry: CellChemistry {
        get { storedChemistry ?? .inferred(fromCellFullVoltage: cellFullVoltage) }
        set { storedChemistry = newValue }
    }

    var expectedPower = 1000         // W, calibrates the power dial
    var expectedRange = 65           // km or mi, calibrates the range dial

    var showPowerDial = true
    var showSpeedDial = true
    var showRangeDial = true

    var chargeLimitEnabled = false
    var alwaysShowChargeLimit = false
    var chargeLimitMode: ChargeLimitMode = .stateOfCharge
    var chargeLimitSOC: Double = 80
    var chargeLimitVoltage: Double = 3.25
    var refillLaterEnabled = false
    var refillDate: Date = .now

    /// Optional on purpose, and read through `refillTarget` rather than directly.
    ///
    /// The synthesized decoder throws on a key that is not in the stored JSON even
    /// when the property has a default, and `DeviceSettingsStore.load` answers a
    /// throw by handing back factory settings — so a plain new field would quietly
    /// cost every already-paired device its name, its charge limit and its hardware
    /// password, which the app cannot recover. An optional decodes as `nil` instead.
    var storedRefillTarget: RefillTarget?

    /// Defaults to the limit, which is what the setting meant when there was no
    /// choice: nothing that is already switched on starts charging further than it
    /// used to.
    var refillTarget: RefillTarget {
        get { storedRefillTarget ?? .chargeLimit }
        set { storedRefillTarget = newValue }
    }
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
