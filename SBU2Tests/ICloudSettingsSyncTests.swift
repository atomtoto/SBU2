//
//  ICloudSettingsSyncTests.swift
//  SBU2Tests
//

import Foundation
import Testing
@testable import SBU2

@Suite("iCloud settings synchronization")
struct ICloudSettingsSyncTests {
    @Test("A fresh installation imports before it considers publishing defaults")
    func freshInstallationDoesNotPublishDefaults() throws {
        let fixture = SyncFixture()
        fixture.sync.start()
        fixture.sync.start()

        #expect(fixture.sync.isEnabled)
        #expect(fixture.cloud.writes.isEmpty)
        #expect(fixture.sync.profiles.isEmpty)

        let publisher = SyncFixture()
        var remote = AppSettings.Snapshot()
        remote.appearance = .dark
        remote.capacityUnit = .wattHours
        publisher.saveApp(remote)
        publisher.sync.start()

        let newDevice = SyncFixture(cloud: FakeICloudStore(records: publisher.cloud.records))
        newDevice.sync.start()
        let imported = try newDevice.loadApp()
        #expect(imported.appearance == .dark)
        #expect(imported.capacityUnit == .wattHours)
        #expect(newDevice.cloud.writes.isEmpty)
    }

    @Test("Existing app preferences migrate once and retain local safety choices")
    func migrationIsIdempotent() throws {
        let fixture = SyncFixture()
        var stored = AppSettings.Snapshot()
        stored.showDemoDevice = false
        stored.capacityUnit = .wattHours
        stored.appearance = .dark
        stored.highContrastFigures = true
        stored.keepScreenAwake = true
        stored.showMOSFETWarning = false
        fixture.saveApp(stored)

        fixture.sync.start()
        let migrated = fixture.cloud.records
        #expect(migrated.keys.filter { $0.hasPrefix("sbu2.v1.app.") }.count == 4)

        let repeated = ICloudSettingsSync(defaults: fixture.defaults,
                                         cloud: fixture.cloud,
                                         notifications: NotificationCenter(),
                                         accountIdentity: ICloudAccountIdentity(tokenProvider: { nil }))
        repeated.start()
        repeated.synchronize()
        #expect(fixture.cloud.records == migrated)
        #expect(try fixture.loadApp() == stored)

        for data in migrated.values {
            let text = String(decoding: data, as: UTF8.self)
            #expect(!text.contains("keepScreenAwake"))
            #expect(!text.contains("showMOSFETWarning"))
        }
    }

    @Test("A remote preference beats the first migration of older local preferences")
    func remoteWinsInitialMigration() throws {
        let publisher = SyncFixture()
        publisher.sync.start()
        var latest = AppSettings.Snapshot()
        latest.appearance = .dark
        publisher.saveApp(latest)
        publisher.sync.appSettingsDidChange(latest)

        let recipient = SyncFixture(cloud: FakeICloudStore(records: publisher.cloud.records))
        var oldLocal = AppSettings.Snapshot()
        oldLocal.appearance = .light
        oldLocal.keepScreenAwake = true
        oldLocal.showMOSFETWarning = false
        recipient.saveApp(oldLocal)
        recipient.sync.start()

        let merged = try recipient.loadApp()
        #expect(merged.appearance == .dark)
        #expect(merged.keepScreenAwake)
        #expect(!merged.showMOSFETWarning)
    }

    @Test("A late initial iCloud download wins without migration overwriting its canonical record")
    func lateInitialSyncPreservesRemoteChoice() throws {
        let publisher = SyncFixture()
        publisher.sync.start()
        var remote = AppSettings.Snapshot()
        remote.appearance = .dark
        remote.capacityUnit = .wattHours
        publisher.saveApp(remote)
        publisher.sync.appSettingsDidChange(remote)
        let canonicalKey = "sbu2.v1.app.appearance"
        let canonicalRecord = try #require(publisher.cloud.records[canonicalKey])

        let recipient = SyncFixture()
        var legacy = AppSettings.Snapshot()
        legacy.appearance = .light
        legacy.capacityUnit = .ampereHours
        legacy.keepScreenAwake = true
        legacy.showMOSFETWarning = false
        recipient.saveApp(legacy)
        recipient.sync.start()

        #expect(recipient.cloud.records[canonicalKey] == nil)
        #expect(!recipient.cloud.writes.contains(canonicalKey))
        // The system cache can be empty at startup even though this account
        // already has preferences. It delivers them later via InitialSync.
        recipient.cloud.records.merge(publisher.cloud.records) { _, remote in remote }
        recipient.cloud.writes.removeAll()
        recipient.sync.receiveExternalChange(reason: NSUbiquitousKeyValueStoreInitialSyncChange,
                                             keys: Array(publisher.cloud.records.keys))
        recipient.sync.synchronize()

        let imported = try recipient.loadApp()
        #expect(imported.appearance == .dark)
        #expect(imported.capacityUnit == .wattHours)
        #expect(imported.keepScreenAwake)
        #expect(!imported.showMOSFETWarning)
        #expect(recipient.cloud.records[canonicalKey] == canonicalRecord)
        #expect(recipient.cloud.writes.isEmpty)
    }

    @Test("Editing different app fields on stale replicas preserves both choices")
    func independentAppFieldsMerge() throws {
        let first = SyncFixture()
        first.saveApp(AppSettings.Snapshot())
        first.sync.start()
        let second = SyncFixture(cloud: FakeICloudStore(records: first.cloud.records))
        second.sync.start()
        first.cloud.writes.removeAll()
        second.cloud.writes.removeAll()

        var firstChoice = try first.loadApp()
        firstChoice.appearance = .dark
        first.saveApp(firstChoice)
        first.sync.appSettingsDidChange(firstChoice)

        var secondChoice = try second.loadApp()
        secondChoice.capacityUnit = .wattHours
        second.saveApp(secondChoice)
        second.sync.appSettingsDidChange(secondChoice)

        #expect(first.cloud.writes.count == 1)
        #expect(second.cloud.writes.count == 1)
        let firstKey = try #require(first.cloud.writes.first)
        let secondKey = try #require(second.cloud.writes.first)
        #expect(firstKey != secondKey)

        var mergedCloud = first.cloud.records
        mergedCloud[secondKey] = second.cloud.records[secondKey]
        first.cloud.records = mergedCloud
        second.cloud.records = mergedCloud
        first.sync.receiveExternalChange(reason: NSUbiquitousKeyValueStoreServerChange, keys: nil)
        second.sync.receiveExternalChange(reason: NSUbiquitousKeyValueStoreServerChange, keys: nil)

        for fixture in [first, second] {
            let settings = try fixture.loadApp()
            #expect(settings.appearance == .dark)
            #expect(settings.capacityUnit == .wattHours)
        }
    }

    @Test("A shared profile uses an explicit local alias and never exports credentials")
    func profilesLinkDifferentPeripheralIdentifiers() throws {
        let publisher = SyncFixture()
        var original = DeviceSettings()
        original.name = "Van"
        original.protocolID = .jbd
        original.kind = .vehicle
        original.expectedRange = 120
        original.storedIcon = .emoji("🚐")
        original.password = "SUPER-SECRET-123456"
        original.hasPassword = true
        original.autoConnect = true
        publisher.saveDevice(original, id: "PHONE-PERIPHERAL")
        publisher.sync.start()
        #expect(publisher.sync.profiles.isEmpty)

        publisher.sync.shareDevice("PHONE-PERIPHERAL", fallbackName: "Battery")
        let profileID = try #require(publisher.sync.profileID(for: "PHONE-PERIPHERAL"))
        let key = "sbu2.v1.profile.\(profileID)"
        let record = try JSONDecoder().decode(TestSyncRecord.self,
                                             from: #require(publisher.cloud.records[key]))
        let payload = try JSONDecoder().decode(TestProfilePayload.self,
                                              from: #require(record.payload))
        let preferences = try #require(JSONSerialization.jsonObject(with: payload.preferences) as? [String: Any])
        #expect(preferences["password"] == nil)
        #expect(preferences["hasPassword"] == nil)
        #expect(preferences["autoConnect"] == nil)
        #expect(!String(decoding: payload.preferences, as: UTF8.self).contains(original.password))
        #expect(!String(decoding: record.payload ?? Data(), as: UTF8.self).contains("PHONE-PERIPHERAL"))

        let recipient = SyncFixture(cloud: FakeICloudStore(records: publisher.cloud.records))
        var local = DeviceSettings()
        local.name = "Locally discovered pack"
        local.password = "TABLET-LOCAL-PASSWORD"
        local.hasPassword = true
        local.autoConnect = false
        local.protocolID = .jbd
        recipient.saveDevice(local, id: "TABLET-PERIPHERAL")
        recipient.sync.start()

        #expect(recipient.sync.profiles.contains { $0.id == profileID && $0.label == "Van" })
        #expect(recipient.sync.profileID(for: "TABLET-PERIPHERAL") == nil)
        #expect(recipient.defaults.data(forKey: "device.settings.PHONE-PERIPHERAL") == nil)
        #expect(try recipient.loadDevice("TABLET-PERIPHERAL").name == local.name)
        #expect(recipient.sync.linkDevice("TABLET-PERIPHERAL", to: profileID))

        let linked = try recipient.loadDevice("TABLET-PERIPHERAL")
        #expect(linked.name == original.name)
        #expect(linked.kind == original.kind)
        #expect(linked.expectedRange == original.expectedRange)
        #expect(linked.storedIcon == original.storedIcon)
        #expect(linked.password == local.password)
        #expect(linked.hasPassword == local.hasPassword)
        #expect(linked.autoConnect == local.autoConnect)
    }

    @Test("Remote profile updates apply once without echoing or replacing local credentials")
    func remoteProfileUpdatesDoNotEcho() throws {
        let publisher = SyncFixture()
        var initial = DeviceSettings()
        initial.name = "Battery"
        publisher.saveDevice(initial, id: "A")
        publisher.sync.start()
        publisher.sync.shareDevice("A", fallbackName: "Battery")
        let profileID = try #require(publisher.sync.profileID(for: "A"))

        let recipient = SyncFixture(cloud: FakeICloudStore(records: publisher.cloud.records))
        var local = DeviceSettings()
        local.password = "local-password"
        local.hasPassword = true
        local.autoConnect = true
        recipient.saveDevice(local, id: "B")
        recipient.sync.start()
        #expect(recipient.sync.linkDevice("B", to: profileID))
        recipient.cloud.writes.removeAll()

        initial.name = "Van battery"
        initial.chargeLimitSOC = 90
        publisher.saveDevice(initial, id: "A")
        publisher.sync.deviceSettingsDidChange(initial, for: "A")
        recipient.cloud.records = publisher.cloud.records
        recipient.sync.receiveExternalChange(reason: NSUbiquitousKeyValueStoreServerChange,
                                             keys: ["sbu2.v1.profile.\(profileID)"])
        let imported = try recipient.loadDevice("B")
        recipient.sync.deviceSettingsDidChange(imported, for: "B")
        recipient.sync.synchronize()

        #expect(imported.name == "Van battery")
        #expect(imported.chargeLimitSOC == 90)
        #expect(imported.password == local.password)
        #expect(imported.autoConnect == local.autoConnect)
        #expect(recipient.cloud.writes.isEmpty)
    }

    @Test("Unlinking keeps local settings and stops subsequent profile updates")
    func unlinkIsLocal() throws {
        let publisher = SyncFixture()
        var settings = DeviceSettings()
        settings.name = "Van"
        publisher.saveDevice(settings, id: "A")
        publisher.sync.start()
        publisher.sync.shareDevice("A", fallbackName: "Battery")
        let profileID = try #require(publisher.sync.profileID(for: "A"))
        let recipient = SyncFixture(cloud: FakeICloudStore(records: publisher.cloud.records))
        recipient.saveDevice(DeviceSettings(), id: "B")
        recipient.sync.start()
        #expect(recipient.sync.linkDevice("B", to: profileID))

        recipient.sync.unlinkDevice("B")
        #expect(recipient.sync.profileID(for: "B") == nil)
        #expect(try recipient.loadDevice("B").name == "Van")
        settings.name = "Renamed on another device"
        publisher.saveDevice(settings, id: "A")
        publisher.sync.deviceSettingsDidChange(settings, for: "A")
        recipient.cloud.records = publisher.cloud.records
        recipient.sync.receiveExternalChange(reason: NSUbiquitousKeyValueStoreServerChange, keys: nil)
        #expect(try recipient.loadDevice("B").name == "Van")
    }

    @Test("A forgotten profile cannot return from an older offline copy or a relaunch")
    func tombstonesPreventResurrection() throws {
        let publisher = SyncFixture()
        var settings = DeviceSettings()
        settings.name = "Van"
        publisher.saveDevice(settings, id: "A")
        publisher.sync.start()
        publisher.sync.shareDevice("A", fallbackName: "Battery")
        let profileID = try #require(publisher.sync.profileID(for: "A"))
        let staleRecords = publisher.cloud.records

        let recipient = SyncFixture(cloud: FakeICloudStore(records: staleRecords))
        recipient.saveDevice(DeviceSettings(), id: "B")
        recipient.sync.start()
        #expect(recipient.sync.linkDevice("B", to: profileID))
        publisher.sync.forgetDevice("A")
        // The other replica can still edit while it has not seen the deletion.
        // Its newer timestamp must not give a deleted profile a new life.
        var offlineEdit = try recipient.loadDevice("B")
        offlineEdit.name = "Edited while offline"
        recipient.saveDevice(offlineEdit, id: "B")
        recipient.sync.deviceSettingsDidChange(offlineEdit, for: "B")
        recipient.cloud.records = publisher.cloud.records
        recipient.sync.receiveExternalChange(reason: NSUbiquitousKeyValueStoreServerChange, keys: nil)

        #expect(!recipient.sync.profiles.contains { $0.id == profileID })
        #expect(recipient.sync.profileID(for: "B") == nil)
        recipient.cloud.records = staleRecords
        recipient.sync.receiveExternalChange(reason: NSUbiquitousKeyValueStoreServerChange, keys: nil)
        #expect(!recipient.sync.profiles.contains { $0.id == profileID })

        let relaunched = ICloudSettingsSync(defaults: recipient.defaults,
                                            cloud: recipient.cloud,
                                            notifications: NotificationCenter(),
                                            accountIdentity: ICloudAccountIdentity(tokenProvider: { nil }))
        relaunched.start()
        #expect(!relaunched.profiles.contains { $0.id == profileID })
        #expect(relaunched.profileID(for: "B") == nil)
    }

    @Test("A fresh replica ignores a stale active profile when its independent deletion remains")
    func independentDeletionProtectsFreshReplicas() throws {
        let publisher = SyncFixture()
        var shared = DeviceSettings()
        shared.name = "Van"
        publisher.saveDevice(shared, id: "A")
        publisher.sync.start()
        publisher.sync.shareDevice("A", fallbackName: "Battery")
        let profileID = try #require(publisher.sync.profileID(for: "A"))
        let profileKey = "sbu2.v1.profile.\(profileID)"
        var staleActive = try JSONDecoder().decode(TestSyncRecord.self,
                                                   from: #require(publisher.cloud.records[profileKey]))
        // An offline device can submit an active record with a clock ahead of
        // the deleting device. The independent deletion still takes precedence.
        staleActive.modifiedAt = .distantFuture
        publisher.sync.forgetDevice("A")
        let deletionKey = "sbu2.v1.deleted.\(profileID)"
        let deletedRecord = try #require(publisher.cloud.records[deletionKey])
        let cloud = FakeICloudStore(records: [
            profileKey: try JSONEncoder().encode(staleActive),
            deletionKey: deletedRecord
        ])
        let recipient = SyncFixture(cloud: cloud)
        var local = DeviceSettings()
        local.name = "Local pack"
        local.password = "local-password"
        recipient.saveDevice(local, id: "B")
        recipient.sync.start()

        #expect(recipient.sync.profiles.isEmpty)
        #expect(!recipient.sync.linkDevice("B", to: profileID))
        #expect(recipient.sync.profileID(for: "B") == nil)
        #expect(try recipient.loadDevice("B") == local)
        #expect(recipient.cloud.records[deletionKey] == deletedRecord)
    }

    @Test("Disabled synchronization retains local edits and publishes when explicitly enabled")
    func disabledSyncKeepsLocalChanges() throws {
        let fixture = SyncFixture()
        fixture.sync.start()
        fixture.sync.setEnabled(false)
        fixture.cloud.writes.removeAll()
        var settings = AppSettings.Snapshot()
        settings.appearance = .dark
        fixture.saveApp(settings)
        fixture.sync.appSettingsDidChange(settings)
        fixture.sync.synchronize()

        #expect(!fixture.sync.isEnabled)
        #expect(fixture.cloud.writes.isEmpty)
        #expect(try fixture.loadApp().appearance == .dark)
        fixture.sync.setEnabled(true)
        #expect(fixture.sync.isEnabled)
        #expect(!fixture.cloud.writes.isEmpty)

        let recipient = SyncFixture(cloud: FakeICloudStore(records: fixture.cloud.records))
        recipient.sync.start()
        #expect(try recipient.loadApp().appearance == .dark)
    }

    @Test("Malformed and unsupported records do not overwrite local settings")
    func invalidRemoteRecordsAreIgnored() throws {
        let fixture = SyncFixture()
        var local = AppSettings.Snapshot()
        local.appearance = .light
        local.highContrastFigures = false
        fixture.saveApp(local)
        fixture.sync.start()
        let originalCloud = fixture.cloud.records
        let key = try #require(originalCloud.keys.first { $0.hasPrefix("sbu2.v1.app.") })

        fixture.cloud.records[key] = Data("not JSON".utf8)
        fixture.sync.receiveExternalChange(reason: NSUbiquitousKeyValueStoreServerChange, keys: [key])
        #expect(try fixture.loadApp() == local)

        var unsupported = try JSONDecoder().decode(TestSyncRecord.self,
                                                   from: #require(originalCloud[key]))
        unsupported.schemaVersion = 999
        unsupported.modifiedAt = .distantFuture
        unsupported.payload = Data("false".utf8)
        fixture.cloud.records[key] = try JSONEncoder().encode(unsupported)
        fixture.sync.receiveExternalChange(reason: NSUbiquitousKeyValueStoreServerChange, keys: [key])
        #expect(try fixture.loadApp() == local)
    }

    @Test("Cloud quota refusal preserves local settings and does not overwrite unrelated data")
    func quotaFailureDoesNotLoseLocalData() throws {
        let cloud = FakeICloudStore(records: ["another-app-value": Data(repeating: 0x41, count: 1_000_001)])
        let fixture = SyncFixture(cloud: cloud)
        var local = DeviceSettings()
        local.name = "Van"
        local.password = "local-password"
        local.hasPassword = true
        fixture.saveDevice(local, id: "A")
        fixture.sync.start()
        fixture.sync.shareDevice("A", fallbackName: "Battery")

        #expect(try fixture.loadDevice("A") == local)
        #expect(cloud.writes.isEmpty)
        #expect(cloud.records["another-app-value"]?.count == 1_000_001)
    }

    @Test("A profile waiting for cloud space survives relaunch and publishes on retry")
    func quotaPendingSurvivesRelaunch() throws {
        let cloud = FakeICloudStore(records: ["full-store": Data(repeating: 0x41, count: 1_000_001)])
        let fixture = SyncFixture(cloud: cloud)
        var local = DeviceSettings()
        local.name = "Van"
        fixture.saveDevice(local, id: "A")
        fixture.sync.start()
        fixture.sync.shareDevice("A", fallbackName: "Battery")
        let profileID = try #require(fixture.sync.profileID(for: "A"))
        #expect(cloud.writes.isEmpty)

        cloud.records.removeAll()
        let relaunched = ICloudSettingsSync(defaults: fixture.defaults,
                                            cloud: cloud,
                                            notifications: NotificationCenter(),
                                            accountIdentity: ICloudAccountIdentity(tokenProvider: { nil }))
        relaunched.start()
        #expect(relaunched.profileID(for: "A") == profileID)
        #expect(cloud.records["sbu2.v1.profile.\(profileID)"] != nil)
        #expect(try fixture.loadDevice("A") == local)
    }

    @Test("An oversized custom icon remains local when its profile cannot be uploaded")
    func oversizedProfileRetainsLocalIcon() throws {
        let fixture = SyncFixture()
        var local = DeviceSettings()
        local.name = "Van"
        local.storedIcon = .glyph(Data(repeating: 0x42, count: 1_000_001))
        fixture.saveDevice(local, id: "A")
        fixture.sync.start()
        fixture.sync.shareDevice("A", fallbackName: "Battery")

        #expect(try fixture.loadDevice("A") == local)
        #expect(fixture.cloud.writes.isEmpty)
    }

    @Test("An oversized edit to a shared profile stays local until its icon can be uploaded")
    func oversizedSharedProfilePreservesEditsUntilShrink() throws {
        let fixture = SyncFixture()
        var settings = DeviceSettings()
        settings.name = "Van"
        fixture.saveDevice(settings, id: "A")
        fixture.sync.start()
        fixture.sync.shareDevice("A", fallbackName: "Battery")
        let profileID = try #require(fixture.sync.profileID(for: "A"))
        let key = "sbu2.v1.profile.\(profileID)"
        let uploaded = try #require(fixture.cloud.records[key])
        fixture.cloud.writes.removeAll()

        settings.name = "Van with custom icon"
        settings.expectedRange = 120
        settings.storedIcon = .glyph(Data(repeating: 0x42, count: 1_000_001))
        fixture.saveDevice(settings, id: "A")
        fixture.sync.deviceSettingsDidChange(settings, for: "A")
        fixture.sync.synchronize()
        #expect(try fixture.loadDevice("A") == settings)
        #expect(fixture.cloud.records[key] == uploaded)
        #expect(fixture.cloud.writes.isEmpty)

        // Other preferences can still change while the icon is too large.
        // Reconciliation must preserve that complete local working copy.
        settings.name = "Van latest"
        settings.expectedPower = 2_222
        fixture.saveDevice(settings, id: "A")
        fixture.sync.deviceSettingsDidChange(settings, for: "A")
        fixture.sync.synchronize()
        #expect(try fixture.loadDevice("A") == settings)
        #expect(fixture.cloud.records[key] == uploaded)

        settings.storedIcon = .emoji("🚐")
        fixture.saveDevice(settings, id: "A")
        fixture.sync.deviceSettingsDidChange(settings, for: "A")
        fixture.sync.synchronize()
        #expect(try fixture.loadDevice("A") == settings)
        #expect(fixture.cloud.records[key] != uploaded)

        let recipient = SyncFixture(cloud: FakeICloudStore(records: fixture.cloud.records))
        recipient.saveDevice(DeviceSettings(), id: "B")
        recipient.sync.start()
        #expect(recipient.sync.linkDevice("B", to: profileID))
        let imported = try recipient.loadDevice("B")
        #expect(imported.name == "Van latest")
        #expect(imported.expectedRange == 120)
        #expect(imported.expectedPower == 2_222)
        #expect(imported.storedIcon == .emoji("🚐"))
    }

    @Test("Changing the iCloud account disconnects profiles and requires explicit re-enabling")
    func accountChangeKeepsLocalPreferences() throws {
        let fixture = SyncFixture()
        var local = DeviceSettings()
        local.name = "Van"
        local.password = "local-password"
        fixture.saveDevice(local, id: "A")
        fixture.sync.start()
        fixture.sync.shareDevice("A", fallbackName: "Battery")
        #expect(fixture.sync.profileID(for: "A") != nil)

        fixture.sync.receiveExternalChange(reason: NSUbiquitousKeyValueStoreAccountChange, keys: nil)

        #expect(!fixture.sync.isEnabled)
        #expect(fixture.sync.profileID(for: "A") == nil)
        #expect(fixture.sync.profiles.isEmpty)
        #expect(try fixture.loadDevice("A") == local)
    }
}

private final class SyncFixture {
    let defaults: UserDefaults
    let cloud: FakeICloudStore
    let sync: ICloudSettingsSync
    private let suiteName: String

    init(cloud: FakeICloudStore = FakeICloudStore()) {
        let suiteName = "SBU2.ICloudSettingsSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        self.suiteName = suiteName
        self.defaults = defaults
        self.cloud = cloud
        sync = ICloudSettingsSync(defaults: defaults, cloud: cloud,
                                 notifications: NotificationCenter(),
                                 accountIdentity: ICloudAccountIdentity(tokenProvider: { nil }))
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func saveApp(_ snapshot: AppSettings.Snapshot) {
        defaults.set(try! JSONEncoder().encode(snapshot), forKey: "app.settings")
    }

    func loadApp() throws -> AppSettings.Snapshot {
        try JSONDecoder().decode(AppSettings.Snapshot.self,
                                 from: #require(defaults.data(forKey: "app.settings")))
    }

    func saveDevice(_ settings: DeviceSettings, id: String) {
        defaults.set(try! JSONEncoder().encode(settings), forKey: "device.settings.\(id)")
    }

    func loadDevice(_ id: String) throws -> DeviceSettings {
        try JSONDecoder().decode(DeviceSettings.self,
                                 from: #require(defaults.data(forKey: "device.settings.\(id)")))
    }
}

private final class FakeICloudStore: ICloudKeyValueStore {
    var records: [String: Data]
    var writes: [String] = []
    var synchronizeResult = true

    init(records: [String: Data] = [:]) {
        self.records = records
    }

    var dictionaryRepresentation: [String: Any] { records }

    func data(forKey key: String) -> Data? { records[key] }

    func set(_ value: Data, forKey key: String) {
        records[key] = value
        writes.append(key)
    }

    func synchronize() -> Bool { synchronizeResult }
}

private struct TestSyncRecord: Codable {
    var schemaVersion: Int
    var modifiedAt: Date
    var changeID: String
    var payload: Data?
}

private struct TestProfilePayload: Codable {
    var id: String
    var label: String
    var protocolID: BMSProtocolID?
    var preferences: Data
}
