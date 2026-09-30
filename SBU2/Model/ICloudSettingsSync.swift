import Foundation
import Observation

/// Small, injectable surface of Apple's ubiquitous store. UserDefaults remains
/// the working copy; iCloud is only the transport for explicitly shared settings.
protocol ICloudKeyValueStore: AnyObject {
    var dictionaryRepresentation: [String: Any] { get }
    func data(forKey key: String) -> Data?
    func set(_ value: Data, forKey key: String)
    func synchronize() -> Bool
}

private final class UbiquitousSettingsStore: ICloudKeyValueStore {
    private let store = NSUbiquitousKeyValueStore.default
    var dictionaryRepresentation: [String: Any] { store.dictionaryRepresentation }
    func data(forKey key: String) -> Data? { store.data(forKey: key) }
    func set(_ value: Data, forKey key: String) { store.set(value, forKey: key) }
    func synchronize() -> Bool { store.synchronize() }
}

struct SyncedDeviceProfile: Identifiable, Equatable {
    let id: String
    let label: String
    let protocolID: BMSProtocolID?
}

/// Accessed on the UI/main queue, like AppSettings and BMSConnection. The store
/// keeps a durable outbox and revisions so delayed/offline writes cannot undo a
/// newer record. A deleted profile ID is never reused.
@Observable
final class ICloudSettingsSync {
    static let shared = ICloudSettingsSync(defaults: .standard, cloud: UbiquitousSettingsStore())
    static let didChange = Notification.Name("SBU2.settingsDidChange")

    struct Record: Codable, Equatable {
        var schemaVersion = 1
        var modifiedAt: Date
        var changeID: String
        var payload: Data?

        func isNewer(than other: Record) -> Bool {
            if modifiedAt != other.modifiedAt { return modifiedAt > other.modifiedAt }
            return changeID > other.changeID
        }
    }

    struct DeviceProfilePayload: Codable {
        var id: String
        var label: String
        var protocolID: BMSProtocolID?
        var preferences: Data
    }

    private static let appPrefix = "sbu2.v1.app."
    private static let profilePrefix = "sbu2.v1.profile."
    private static let deletionPrefix = "sbu2.v1.deleted."
    // Leave room for property-list overhead within Apple's 1 MB quota.
    private static let byteBudget = 1_000_000
    private static let appFields = ["showDemoDevice", "capacityUnit", "appearance", "highContrastFigures"]
    /// A whitelist prevents a future credential field from accidentally being
    /// uploaded. Missing optional values must also clear the receiving choice.
    private static let deviceFields: Set<String> = [
        "name", "kind", "protocolID", "cellEmptyVoltage", "cellNominalVoltage",
        "cellFullVoltage", "storedChemistry", "expectedPower", "expectedRange",
        "showPowerDial", "showSpeedDial", "showRangeDial", "storedSpeedDialStyle",
        "storedSpeedDialMaximum", "storedRadioSpeedIndicatorStyle", "storedGPSLandscapeLayout",
        "chargeLimitEnabled", "alwaysShowChargeLimit", "chargeLimitMode", "chargeLimitSOC",
        "chargeLimitVoltage", "refillLaterEnabled", "refillDate", "storedRefillTarget",
        "storedIcon", "storedOverviewStyle", "storedCellVoltageStyle"
    ]
    private static let requiredDeviceFields: Set<String> = [
        "name", "kind", "cellEmptyVoltage", "cellNominalVoltage", "cellFullVoltage",
        "expectedPower", "expectedRange", "showPowerDial", "showSpeedDial", "showRangeDial",
        "chargeLimitEnabled", "alwaysShowChargeLimit", "chargeLimitMode", "chargeLimitSOC",
        "chargeLimitVoltage", "refillLaterEnabled", "refillDate"
    ]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cloud: ICloudKeyValueStore
    @ObservationIgnored private let notifications: NotificationCenter
    @ObservationIgnored private let accountIdentity: ICloudAccountIdentity
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var records: [String: Data]
    @ObservationIgnored private var pending: [String: Data]
    @ObservationIgnored private var bindings: [String: String]
    @ObservationIgnored private var oversizedDevices: Set<String>
    @ObservationIgnored private let installationID: String
    private(set) var revision = 0
    private var enabled: Bool
    private var problem: String?

    var isEnabled: Bool { enabled }
    var statusText: String {
        if let problem { return problem }
        if !enabled { return "Off — settings are saved on this device." }
        return "On — iCloud transfers changes when available."
    }

    var profiles: [SyncedDeviceProfile] {
        _ = revision
        return records.compactMap { key, data in
            guard let payload = profilePayload(key: key, data: data) else { return nil }
            return SyncedDeviceProfile(id: payload.id, label: payload.label, protocolID: payload.protocolID)
        }.sorted {
            if $0.label != $1.label { return $0.label.localizedStandardCompare($1.label) == .orderedAscending }
            return $0.id < $1.id
        }
    }

    init(defaults: UserDefaults, cloud: ICloudKeyValueStore, notifications: NotificationCenter = .default,
         accountIdentity: ICloudAccountIdentity = ICloudAccountIdentity()) {
        self.defaults = defaults
        self.cloud = cloud
        self.notifications = notifications
        self.accountIdentity = accountIdentity
        enabled = defaults.object(forKey: "sync.enabled") as? Bool ?? true
        records = defaults.dictionary(forKey: "sync.records") as? [String: Data] ?? [:]
        pending = defaults.dictionary(forKey: "sync.pending") as? [String: Data] ?? [:]
        bindings = defaults.dictionary(forKey: "sync.bindings") as? [String: String] ?? [:]
        oversizedDevices = Set(defaults.stringArray(forKey: "sync.oversizedDevices") ?? [])
        installationID = defaults.string(forKey: "sync.installationID") ?? UUID().uuidString
        defaults.set(installationID, forKey: "sync.installationID")
    }

    deinit {
        if let observer { notifications.removeObserver(observer) }
    }

    func start() {
        guard !started else { return }
        started = true
        observer = notifications.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                             object: nil, queue: .main) { [weak self] note in
            guard let reason = (note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? NSNumber)?.intValue else { return }
            self?.receiveExternalChange(reason: reason,
                                        keys: note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String])
        }
        guard enabled else { return }
        synchronize()
    }

    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        defaults.set(enabled, forKey: "sync.enabled")
        problem = nil
        if enabled {
            if !started { start() } else { synchronize() }
        }
        changed()
    }

    func synchronize() {
        guard started, enabled else { return }
        guard !accountIdentity.accountChanged(defaults: defaults) else {
            suspendForAccountChange()
            return
        }
        // This refreshes the system cache; it is not a network-completion signal.
        _ = cloud.synchronize()
        reconcile(keys: nil)
        seedStoredAppPreferences()
        flushPending()
        changed()
    }

    func receiveExternalChange(reason: Int, keys: [String]?) {
        guard started else { return }
        if reason == NSUbiquitousKeyValueStoreAccountChange {
            // Never automatically copy the previous account's profiles/outbox to
            // a different Apple account. Re-enabling is an explicit new choice.
            _ = accountIdentity.accountChanged(defaults: defaults)
            suspendForAccountChange()
            return
        }
        guard enabled else { return }
        if reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
            problem = "iCloud storage is full. Changes remain saved on this device."
            // Retain even submitted writes for a later retry after the quota error.
            pending.merge(records) { current, _ in current }
            saveState()
            changed()
            return
        }
        guard reason == NSUbiquitousKeyValueStoreServerChange
                || reason == NSUbiquitousKeyValueStoreInitialSyncChange else { return }
        reconcile(keys: keys)
        seedStoredAppPreferences()
        flushPending()
        changed()
    }

    func appSettingsDidChange(_ snapshot: AppSettings.Snapshot) {
        guard started else { return }
        for (field, value) in appValues(snapshot) {
            let key = Self.appPrefix + field
            guard appRecord(field: field)?.payload != value else { continue }
            stage(payload: value, for: key)
        }
        if enabled { flushPending() }
    }

    func deviceSettingsDidChange(_ settings: DeviceSettings, for id: String) {
        guard started else { return }
        defer { changed() }
        guard let profileID = bindings[id] else { return }
        let key = Self.profilePrefix + profileID
        guard let current = profilePayload(key: key, data: records[key]),
              let preferences = sharedDevicePreferences(settings) else { return }
        if preferences == current.preferences {
            if oversizedDevices.remove(id) != nil {
                saveState()
                if enabled { flushPending() }
            }
            return
        }
        let payload = DeviceProfilePayload(id: profileID,
                                          label: settings.name.isEmpty ? current.label : settings.name,
                                          protocolID: settings.protocolID,
                                          preferences: preferences)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        if stage(payload: data, for: key) {
            oversizedDevices.remove(id)
        } else {
            oversizedDevices.insert(id)
        }
        saveState()
        if enabled { flushPending() }
    }

    func profileID(for deviceID: String) -> String? {
        _ = revision
        guard let id = bindings[deviceID],
              profilePayload(key: Self.profilePrefix + id, data: records[Self.profilePrefix + id]) != nil else { return nil }
        return id
    }

    func availableProfiles(for protocolID: BMSProtocolID) -> [SyncedDeviceProfile] {
        profiles.filter { $0.protocolID == nil || $0.protocolID == protocolID }
    }

    func shareDevice(_ id: String, fallbackName: String) {
        guard started, enabled, profileID(for: id) == nil else { return }
        let settings = localDeviceSettings(id)
        guard let preferences = sharedDevicePreferences(settings) else { return }
        let profileID = UUID().uuidString
        let payload = DeviceProfilePayload(id: profileID,
                                          label: settings.name.isEmpty ? fallbackName : settings.name,
                                          protocolID: settings.protocolID,
                                          preferences: preferences)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        guard stage(payload: data, for: Self.profilePrefix + profileID) else {
            oversizedDevices.insert(id)
            saveState()
            changed()
            return
        }
        oversizedDevices.remove(id)
        bindings[id] = profileID
        saveState()
        flushPending()
        changed()
    }

    @discardableResult
    func linkDevice(_ id: String, to profileID: String) -> Bool {
        guard started, enabled,
              let payload = profilePayload(key: Self.profilePrefix + profileID,
                                           data: records[Self.profilePrefix + profileID]) else { return false }
        let local = localDeviceSettings(id)
        guard local.protocolID == nil || payload.protocolID == nil || local.protocolID == payload.protocolID,
              let merged = mergingDevicePreferences(payload.preferences, into: local) else { return false }
        bindings[id] = profileID
        oversizedDevices.remove(id)
        storeLocalDevice(merged, id: id)
        saveState()
        changed()
        return true
    }

    func unlinkDevice(_ id: String) {
        bindings.removeValue(forKey: id)
        oversizedDevices.remove(id)
        saveState()
        changed()
    }

    /// Forgetting a linked profile also forgets its shared choices on the other
    /// linked devices. Credentials and auto-connect belong to each local device.
    func forgetDevice(_ id: String) {
        guard started else { return }
        oversizedDevices.remove(id)
        if let profileID = bindings.removeValue(forKey: id) {
            // A separate key can never be overwritten by an offline live-profile
            // edit. The original profile key is also tombstoned for older clients.
            stage(payload: nil, for: Self.profilePrefix + profileID)
            stage(payload: nil, for: Self.deletionPrefix + profileID)
            applyProfile(key: Self.profilePrefix + profileID)
            if enabled { flushPending() }
        }
        saveState()
        changed()
    }

    private func seedStoredAppPreferences() {
        guard let data = defaults.data(forKey: AppSettings.key),
              let snapshot = try? JSONDecoder().decode(AppSettings.Snapshot.self, from: data) else { return }
        for (field, payload) in appValues(snapshot) {
            guard appRecord(field: field) == nil else { continue }
            // Each installation migrates into its own key, so an empty system
            // cache on the first launch cannot overwrite an as-yet-undownloaded
            // preference in iCloud. Real user edits use the canonical field key.
            let key = Self.appPrefix + field + "." + installationID
            // Migration is older than every real edit, including an initial iCloud
            // download that arrives after launch. Factory defaults are never seeded.
            stage(payload: payload, for: key, date: Date(timeIntervalSince1970: 0))
        }
    }

    @discardableResult
    private func stage(payload: Data?, for key: String, date: Date = .now) -> Bool {
        let previous = decodeRecord(records[key])
        let stamp = max(date, previous?.modifiedAt.addingTimeInterval(0.001) ?? date)
        let record = Record(modifiedAt: stamp, changeID: UUID().uuidString, payload: payload)
        guard let data = try? JSONEncoder().encode(record) else { return false }
        let otherBytes = records.reduce(0) { $0 + ($1.key == key ? 0 : $1.value.count) }
        guard data.count <= Self.byteBudget, otherBytes + data.count <= Self.byteBudget else {
            // Keep oversized edits in the existing local settings, without making
            // two additional copies in UserDefaults and exceeding its own quota.
            problem = "Some settings or icons exceed iCloud storage. They remain saved on this device."
            return false
        }
        records[key] = data
        pending[key] = data
        saveState()
        return true
    }

    private func reconcile(keys: [String]?) {
        let remoteKeys = Set(cloud.dictionaryRepresentation.keys.filter(isSyncKey))
        let relevant = keys.map(Set.init) ?? remoteKeys.union(records.keys)
        for key in relevant where isSyncKey(key) {
            guard let data = cloud.data(forKey: key), let remote = validatedRecord(data, key: key) else { continue }
            let local = decodeRecord(records[key])
            // Deletion is terminal for a profile, even if an offline clock is ahead.
            let isProfile = key.hasPrefix(Self.profilePrefix)
            let remoteDeleted = isProfile && remote.payload == nil
            let localDeleted = isProfile && local?.payload == nil && local != nil
            let acceptRemote = local == nil || remoteDeleted
                || (!localDeleted && remote.isNewer(than: local!))
            if acceptRemote {
                records[key] = data
                pending.removeValue(forKey: key)
            } else if remote == local {
                pending.removeValue(forKey: key)
            } else if let localData = records[key] {
                pending[key] = localData
            }
        }
        // A cache may contain a submitted write not present in this system cache
        // yet. Keep it in the outbox instead of losing it after a restart.
        for key in records.keys where !remoteKeys.contains(key) {
            pending[key] = records[key]
        }
        for key in records.keys where key.hasPrefix(Self.deletionPrefix) {
            guard let deletion = decodeRecord(records[key]), deletion.payload == nil else { continue }
            let profileKey = Self.profilePrefix + key.dropFirst(Self.deletionPrefix.count)
            records[profileKey] = records[key]
            pending.removeValue(forKey: profileKey)
        }
        applyAppPreferences()
        for key in records.keys where key.hasPrefix(Self.profilePrefix) { applyProfile(key: key) }
        saveState()
    }

    private func flushPending() {
        guard enabled else { return }
        guard !accountIdentity.accountChanged(defaults: defaults) else {
            suspendForAccountChange()
            return
        }
        var blocked = false
        for key in pending.keys.sorted() {
            guard let data = pending[key], validatedRecord(data, key: key) != nil else { continue }
            // Do not downgrade a record produced by a newer version of SBU2.
            if let remote = cloud.data(forKey: key), decodeRecord(remote) == nil { continue }
            var proposed = cloud.dictionaryRepresentation
            proposed[key] = data
            let bytes = (try? PropertyListSerialization.data(fromPropertyList: proposed, format: .binary, options: 0).count)
                ?? Int.max
            guard proposed.count <= 1024, bytes <= Self.byteBudget else {
                blocked = true
                continue
            }
            cloud.set(data, forKey: key)
            pending.removeValue(forKey: key)
        }
        problem = blocked || !oversizedDevices.isEmpty
            ? "Some settings or icons exceed iCloud storage. They remain saved on this device." : nil
        saveState()
    }

    private func applyAppPreferences() {
        let stored = defaults.data(forKey: AppSettings.key)
            .flatMap { try? JSONDecoder().decode(AppSettings.Snapshot.self, from: $0) }
        var snapshot = stored ?? AppSettings.Snapshot()
        var found = false
        for field in Self.appFields {
            guard let payload = appRecord(field: field)?.payload else { continue }
            switch field {
            case "showDemoDevice":
                guard let value = try? JSONDecoder().decode(Bool.self, from: payload) else { continue }
                snapshot.showDemoDevice = value
            case "capacityUnit":
                guard let value = try? JSONDecoder().decode(CapacityUnit.self, from: payload) else { continue }
                snapshot.capacityUnit = value
            case "appearance":
                guard let value = try? JSONDecoder().decode(Appearance.self, from: payload) else { continue }
                snapshot.appearance = value
            case "highContrastFigures":
                guard let value = try? JSONDecoder().decode(Bool.self, from: payload) else { continue }
                snapshot.highContrastFigures = value
            default: continue
            }
            found = true
        }
        if found, let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: AppSettings.key) }
    }

    private func applyProfile(key: String) {
        guard let record = decodeRecord(records[key]) else { return }
        let profileID = String(key.dropFirst(Self.profilePrefix.count))
        let deviceIDs = bindings.filter { $0.value == profileID }.map(\.key)
        for id in deviceIDs {
            let local = localDeviceSettings(id)
            if record.payload == nil {
                var reset = DeviceSettings()
                reset.password = local.password
                reset.hasPassword = local.hasPassword
                reset.autoConnect = local.autoConnect
                storeLocalDevice(reset, id: id)
                bindings.removeValue(forKey: id)
                oversizedDevices.remove(id)
            } else if let payload = profilePayload(key: key, data: records[key]),
                      !oversizedDevices.contains(id),
                      let merged = mergingDevicePreferences(payload.preferences, into: local) {
                storeLocalDevice(merged, id: id)
            }
        }
    }

    private func appValues(_ snapshot: AppSettings.Snapshot) -> [String: Data] {
        let encoder = JSONEncoder()
        return ["showDemoDevice": try? encoder.encode(snapshot.showDemoDevice),
                "capacityUnit": try? encoder.encode(snapshot.capacityUnit),
                "appearance": try? encoder.encode(snapshot.appearance),
                "highContrastFigures": try? encoder.encode(snapshot.highContrastFigures ?? false)]
            .compactMapValues { $0 }
    }

    private func sharedDevicePreferences(_ settings: DeviceSettings) -> Data? {
        guard let data = try? JSONEncoder().encode(settings),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return try? JSONSerialization.data(withJSONObject: object.filter { Self.deviceFields.contains($0.key) },
                                           options: [.sortedKeys])
    }

    private func mergingDevicePreferences(_ data: Data, into local: DeviceSettings) -> DeviceSettings? {
        guard let incoming = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Self.requiredDeviceFields.isSubset(of: Set(incoming.keys)),
              Set(incoming.keys).isSubset(of: Self.deviceFields),
              let localData = try? JSONEncoder().encode(local),
              var merged = try? JSONSerialization.jsonObject(with: localData) as? [String: Any] else { return nil }
        for key in Self.deviceFields { merged.removeValue(forKey: key) }
        merged.merge(incoming) { _, incoming in incoming }
        guard let result = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? JSONDecoder().decode(DeviceSettings.self, from: result)
    }

    private func localDeviceSettings(_ id: String) -> DeviceSettings {
        defaults.data(forKey: DeviceSettingsStore.key(for: id))
            .flatMap { try? JSONDecoder().decode(DeviceSettings.self, from: $0) } ?? DeviceSettings()
    }

    private func storeLocalDevice(_ settings: DeviceSettings, id: String) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: DeviceSettingsStore.key(for: id))
    }

    private func isSyncKey(_ key: String) -> Bool {
        for prefix in [Self.profilePrefix, Self.deletionPrefix] where key.hasPrefix(prefix) {
            return UUID(uuidString: String(key.dropFirst(prefix.count))) != nil
        }
        return appField(for: key) != nil
    }

    private func appField(for key: String) -> String? {
        guard key.hasPrefix(Self.appPrefix) else { return nil }
        let components = key.dropFirst(Self.appPrefix.count).split(separator: ".", omittingEmptySubsequences: false)
        guard let first = components.first, Self.appFields.contains(String(first)),
              components.count == 1 || (components.count == 2 && UUID(uuidString: String(components[1])) != nil) else { return nil }
        return String(first)
    }

    private func appRecord(field: String) -> Record? {
        records.compactMap { key, data -> Record? in
            guard appField(for: key) == field else { return nil }
            return validatedRecord(data, key: key)
        }.max { $1.isNewer(than: $0) }
    }

    private func decodeRecord(_ data: Data?) -> Record? {
        guard let data, let record = try? JSONDecoder().decode(Record.self, from: data),
              record.schemaVersion == 1, record.modifiedAt.timeIntervalSince1970.isFinite else { return nil }
        return record
    }

    private func validatedRecord(_ data: Data, key: String) -> Record? {
        guard isSyncKey(key), data.count <= Self.byteBudget, let record = decodeRecord(data) else { return nil }
        if key.hasPrefix(Self.deletionPrefix) { return record.payload == nil ? record : nil }
        if key.hasPrefix(Self.profilePrefix) {
            if record.payload == nil { return record }
            return profilePayload(key: key, data: data) == nil ? nil : record
        }
        guard let payload = record.payload else { return nil }
        switch appField(for: key) {
        case "showDemoDevice", "highContrastFigures":
            return (try? JSONDecoder().decode(Bool.self, from: payload)) == nil ? nil : record
        case "appearance":
            return (try? JSONDecoder().decode(Appearance.self, from: payload)) == nil ? nil : record
        case "capacityUnit":
            return (try? JSONDecoder().decode(CapacityUnit.self, from: payload)) == nil ? nil : record
        default: return nil
        }
    }

    private func profilePayload(key: String, data: Data?) -> DeviceProfilePayload? {
        guard key.hasPrefix(Self.profilePrefix), let value = decodeRecord(data)?.payload,
              let payload = try? JSONDecoder().decode(DeviceProfilePayload.self, from: value),
              Self.profilePrefix + payload.id == key,
              UUID(uuidString: payload.id) != nil,
              decodeRecord(records[Self.deletionPrefix + payload.id]) == nil,
              mergingDevicePreferences(payload.preferences, into: DeviceSettings()) != nil else { return nil }
        return payload
    }

    private func saveState() {
        defaults.set(records, forKey: "sync.records")
        defaults.set(pending, forKey: "sync.pending")
        defaults.set(bindings, forKey: "sync.bindings")
        defaults.set(Array(oversizedDevices), forKey: "sync.oversizedDevices")
    }

    private func suspendForAccountChange() {
        enabled = false
        defaults.set(false, forKey: "sync.enabled")
        records.removeAll()
        pending.removeAll()
        bindings.removeAll()
        oversizedDevices.removeAll()
        saveState()
        problem = "Apple account changed. Enable sync to use the current account."
        changed()
    }

    private func changed() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.changed() }
            return
        }
        revision &+= 1
        notifications.post(name: Self.didChange, object: self)
    }
}
