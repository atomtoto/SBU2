//
//  BMSConnection.swift
//  SBU2
//

import CoreBluetooth
import Foundation
import Observation

/// A BMS the app can open: a dongle seen while scanning, or the built-in demo pack.
struct DiscoveredBMS: Identifiable, Hashable {
    let id: String
    var name: String
    var rssi: Int?
    var isDemo: Bool

    fileprivate var peripheral: CBPeripheral?

    static func == (lhs: DiscoveredBMS, rhs: DiscoveredBMS) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Scans for JBD dongles, keeps one open and polls it for live values.
///
/// The central manager runs on the main queue, so every delegate callback already
/// happens where the observable state is read from.
@Observable
final class BMSConnection: NSObject {

    enum Status: Equatable {
        case bluetoothOff
        case unauthorized
        case unsupported
        case idle
        case scanning
        case connecting(String)
        case connected(String)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    /// What the BMS said about the last write.
    enum WriteOutcome: Equatable {
        case idle
        case succeeded
        case rejected(String)
    }

    private static let serviceUUID = CBUUID(string: "FF00")
    private static let notifyUUID = CBUUID(string: "FF01")
    private static let writeUUID = CBUUID(string: "FF02")
    private static let pollInterval: TimeInterval = 1.0

    // MARK: Observable state

    private(set) var status: Status = .idle
    private(set) var discovered: [DiscoveredBMS] = []
    private(set) var info = BasicInfo()
    private(set) var cellVoltages: [Double] = []
    private(set) var lastUpdate: Date?
    private(set) var lastError: String?
    private(set) var isWritingMOS = false
    private(set) var passwordOutcome: WriteOutcome = .idle

    /// Settings of the device currently open. Call `saveSettings()` after changing it —
    /// the `@Observable` macro rewrites stored properties, so `didSet` is not a reliable
    /// place to persist from. The device tabs do that on every change.
    var settings = DeviceSettings()

    private(set) var openDeviceID: String?

    func saveSettings() {
        guard let openDeviceID else { return }
        DeviceSettingsStore.save(settings, for: openDeviceID)
    }

    var cellSummary: CellSummary? { CellSummary(voltages: cellVoltages) }

    // MARK: Internals

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var writeCharacteristic: CBCharacteristic?
    @ObservationIgnored private var assembler = FrameAssembler()
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var wantsConnection = false
    @ObservationIgnored private var demo: DemoDevice?
    @ObservationIgnored private var showDemoDevice = true

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Discovery

    func setShowDemoDevice(_ show: Bool) {
        guard show != showDemoDevice else { return }
        showDemoDevice = show
        refreshDemoEntry()
    }

    private func refreshDemoEntry() {
        discovered.removeAll { $0.isDemo }
        if showDemoDevice {
            var entry = DiscoveredBMS(id: DemoDevice.identifier,
                                      name: "Demo device",
                                      rssi: nil,
                                      isDemo: true,
                                      peripheral: nil)
            entry.name = DeviceSettingsStore.load(DemoDevice.identifier).name.isEmpty
                ? entry.name
                : DeviceSettingsStore.load(DemoDevice.identifier).name
            discovered.insert(entry, at: 0)
        }
    }

    func startScanning() {
        discovered.removeAll { !$0.isDemo }
        refreshDemoEntry()
        guard central.state == .poweredOn else { return }
        status = .scanning
        central.scanForPeripherals(withServices: [Self.serviceUUID])
    }

    /// The device to open automatically, if the user asked for one.
    var autoConnectTarget: DiscoveredBMS? {
        discovered.first { DeviceSettingsStore.load($0.id).autoConnect }
    }

    // MARK: - Opening a device

    func open(_ device: DiscoveredBMS) {
        central.stopScan()
        lastError = nil
        passwordOutcome = .idle
        openDeviceID = device.id
        settings = DeviceSettingsStore.load(device.id)

        if device.isDemo {
            demo = DemoDevice()
            peripheral = nil
            wantsConnection = false
            status = .connected(displayName(for: device))
            startPolling()
            return
        }

        demo = nil
        wantsConnection = true
        peripheral = device.peripheral
        peripheral?.delegate = self
        status = .connecting(displayName(for: device))
        if let peripheral = device.peripheral {
            central.connect(peripheral)
        }
    }

    func close() {
        wantsConnection = false
        stopPolling()
        demo = nil
        openDeviceID = nil
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        } else {
            startScanning()
        }
        resetReadings()
    }

    func displayName(for device: DiscoveredBMS) -> String {
        let stored = DeviceSettingsStore.load(device.id).name
        return stored.isEmpty ? device.name : stored
    }

    private func resetReadings() {
        assembler.reset()
        info = BasicInfo()
        cellVoltages = []
        lastUpdate = nil
        isWritingMOS = false
        writeCharacteristic = nil
    }

    private func abortConnection(_ message: String) {
        lastError = message
        wantsConnection = false
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        } else {
            startScanning()
        }
    }

    // MARK: - Polling

    private func startPolling() {
        stopPolling()
        poll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func poll() {
        if demo != nil {
            demo?.step()
            info = demo?.info ?? BasicInfo()
            cellVoltages = demo?.cellVoltages ?? []
            lastUpdate = .now
            return
        }
        send(JBD.readRequest(.basicInfo))
        send(JBD.readRequest(.cellVoltages))
    }

    private func send(_ bytes: [UInt8]) {
        guard let peripheral, let writeCharacteristic, peripheral.state == .connected else { return }
        peripheral.writeValue(Data(bytes), for: writeCharacteristic, type: .withoutResponse)
    }

    // MARK: - Writes

    /// Every write has to be bracketed: unlock if the pack is protected, open factory
    /// mode, write, then close it again.
    private func write(_ command: [UInt8]) {
        if settings.hasPassword, let unlock = JBD.enterPassword(settings.password) {
            send(unlock)
        }
        send(JBD.openFactoryMode)
        send(command)
        send(JBD.closeFactoryMode)
    }

    var canControlMOS: Bool {
        status.isConnected && settings.liontronMode != .autoEnabled
    }

    func setMOS(charge: Bool, discharge: Bool) {
        guard status.isConnected else { return }
        lastError = nil

        if demo != nil {
            demo?.setMOS(charge: charge, discharge: discharge)
            info = demo?.info ?? info
            return
        }

        isWritingMOS = true
        write(JBD.mosControl(charge: charge, discharge: discharge))
        // The switches reflect what the BMS reports, so release the UI once the next
        // poll has had time to land.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pollInterval * 2) { [weak self] in
            self?.isWritingMOS = false
        }
    }

    // MARK: - Hardware password

    func createPassword(_ new: String) {
        guard let command = JBD.createPassword(new) else { return }
        passwordOutcome = .idle
        send(JBD.openFactoryMode)
        send(command)
        send(JBD.closeFactoryMode)
        settings.password = new
        settings.hasPassword = true
        saveSettings()
    }

    func changePassword(to new: String) {
        guard let command = JBD.changePassword(from: settings.password, to: new) else { return }
        passwordOutcome = .idle
        if let unlock = JBD.enterPassword(settings.password) { send(unlock) }
        send(JBD.openFactoryMode)
        send(command)
        send(JBD.closeFactoryMode)
        settings.password = new
        saveSettings()
    }

    func removePassword() {
        passwordOutcome = .idle
        if let unlock = JBD.enterPassword(settings.password) { send(unlock) }
        send(JBD.openFactoryMode)
        send(JBD.clearPassword)
        send(JBD.closeFactoryMode)
        settings.hasPassword = false
        settings.password = "000000"
        saveSettings()
    }

    // MARK: - Incoming frames

    private func handle(_ frame: [UInt8]) {
        guard let response = try? JBD.decode(frame) else { return }

        guard response.isOK else {
            handleError(register: response.register, status: response.status)
            return
        }

        switch response.register {
        case JBD.Register.basicInfo.rawValue:
            if let decoded = BasicInfo.decode(payload: response.payload) {
                info = decoded
                lastUpdate = .now
            }
        case JBD.Register.cellVoltages.rawValue:
            cellVoltages = CellVoltages.decode(payload: response.payload)
            lastUpdate = .now
        case JBD.Register.enterPassword.rawValue,
             JBD.Register.setPassword.rawValue,
             JBD.Register.clearPassword.rawValue:
            passwordOutcome = .succeeded
        default:
            break
        }
    }

    private func handleError(register: UInt8, status: UInt8) {
        switch register {
        case JBD.Register.enterPassword.rawValue,
             JBD.Register.setPassword.rawValue,
             JBD.Register.clearPassword.rawValue:
            passwordOutcome = .rejected("The BMS rejected the password.")
            settings.hasPassword = true
            saveSettings()
        case JBD.Register.mosControl.rawValue, JBD.Register.factoryModeOpen.rawValue:
            // 0x80 on a factory-mode write is how a hardware-locked Liontron pack answers.
            if status == 0x80, settings.liontronMode == .autoDisabled {
                settings.liontronMode = .autoEnabled
                saveSettings()
            }
            lastError = settings.hasPassword
                ? "The BMS rejected the command. Check the password."
                : "The BMS rejected the command. This pack may be hardware locked."
        default:
            break
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BMSConnection: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            status = .idle
            startScanning()
        case .poweredOff:
            status = .bluetoothOff
            discovered.removeAll { !$0.isDemo }
            refreshDemoEntry()
        case .unauthorized:
            status = .unauthorized
        case .unsupported:
            status = .unsupported
        default:
            status = .idle
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let advertised = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
            ?? "BMS inconnu"
        let device = DiscoveredBMS(id: peripheral.identifier.uuidString,
                                   name: advertised,
                                   rssi: RSSI.intValue,
                                   isDemo: false,
                                   peripheral: peripheral)

        if let index = discovered.firstIndex(where: { $0.id == device.id }) {
            discovered[index] = device
        } else {
            discovered.append(device)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        assembler.reset()
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        wantsConnection = false
        self.peripheral = nil
        lastError = error?.localizedDescription ?? "Could not connect."
        startScanning()
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        stopPolling()
        resetReadings()
        guard wantsConnection else {
            self.peripheral = nil
            startScanning()
            return
        }
        // Dongles drop the link regularly; reconnecting keeps the dashboard live.
        status = .connecting(peripheral.name ?? "BMS")
        central.connect(peripheral)
    }
}

// MARK: - CBPeripheralDelegate

extension BMSConnection: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            abortConnection("Service FF00 not found on this device.")
            return
        }
        peripheral.discoverCharacteristics([Self.notifyUUID, Self.writeUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case Self.notifyUUID:
                peripheral.setNotifyValue(true, for: characteristic)
            case Self.writeUUID:
                writeCharacteristic = characteristic
            default:
                break
            }
        }
        guard writeCharacteristic != nil else {
            abortConnection("Write characteristic FF02 not found.")
            return
        }
        status = .connected(peripheral.name ?? "BMS")
        startPolling()
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value else { return }
        for frame in assembler.append(data) {
            handle(frame)
        }
    }
}
