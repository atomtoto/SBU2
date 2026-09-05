//
//  BMSConnection.swift
//  SBU2
//

import CoreBluetooth
import Foundation
import Observation

/// A JBD dongle seen while scanning.
struct DiscoveredBMS: Identifiable, Hashable {
    let id: UUID
    var name: String
    var rssi: Int

    fileprivate var peripheral: CBPeripheral

    static func == (lhs: DiscoveredBMS, rhs: DiscoveredBMS) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Scans for JBD dongles, keeps one connected and polls it for live values.
///
/// The central manager is created on the main queue, so every delegate callback
/// already runs where the observable state is read from.
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

    // The dongle exposes one serial-like service: FF01 notifies, FF02 accepts writes.
    private static let serviceUUID = CBUUID(string: "FF00")
    private static let notifyUUID = CBUUID(string: "FF01")
    private static let writeUUID = CBUUID(string: "FF02")

    /// How often a full basic-info + cell-voltage pair is requested.
    private static let pollInterval: TimeInterval = 1.0

    private(set) var status: Status = .idle
    private(set) var discovered: [DiscoveredBMS] = []
    private(set) var info = BasicInfo()
    private(set) var cellVoltages: [Double] = []
    private(set) var lastUpdate: Date?
    private(set) var lastError: String?

    /// Set while a MOSFET write is in flight, so the UI can disable the switches.
    private(set) var isWritingMOS = false

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var writeCharacteristic: CBCharacteristic?
    @ObservationIgnored private var assembler = FrameAssembler()
    @ObservationIgnored private var pollTimer: Timer?
    /// Cleared when the user leaves the monitor, so `didDisconnect` does not reconnect.
    @ObservationIgnored private var wantsConnection = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Scanning & connection

    func startScanning() {
        guard central.state == .poweredOn else { return }
        discovered.removeAll()
        status = .scanning
        central.scanForPeripherals(withServices: [Self.serviceUUID])
    }

    func connect(to device: DiscoveredBMS) {
        central.stopScan()
        wantsConnection = true
        lastError = nil
        peripheral = device.peripheral
        peripheral?.delegate = self
        status = .connecting(device.name)
        central.connect(device.peripheral)
    }

    func disconnect() {
        wantsConnection = false
        stopPolling()
        if let peripheral {
            // Scanning resumes from `didDisconnectPeripheral`, once the link is really down.
            central.cancelPeripheralConnection(peripheral)
        } else {
            startScanning()
        }
        resetReadings()
    }

    /// Gives up on the current peripheral: no reconnection attempt, back to scanning.
    private func abortConnection(_ message: String) {
        lastError = message
        wantsConnection = false
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        } else {
            startScanning()
        }
    }

    private func resetReadings() {
        assembler.reset()
        info = BasicInfo()
        cellVoltages = []
        lastUpdate = nil
        isWritingMOS = false
        writeCharacteristic = nil
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
        send(JBD.readRequest(.basicInfo))
        send(JBD.readRequest(.cellVoltages))
    }

    private func send(_ bytes: [UInt8]) {
        guard let peripheral, let writeCharacteristic, peripheral.state == .connected else { return }
        peripheral.writeValue(Data(bytes), for: writeCharacteristic, type: .withoutResponse)
    }

    // MARK: - MOSFET control

    /// Toggles the charge/discharge MOSFETs. The BMS only accepts the write while
    /// factory mode is open, so the three frames are always sent together.
    func setMOS(charge: Bool, discharge: Bool) {
        guard status.isConnected else { return }
        lastError = nil
        isWritingMOS = true
        send(JBD.openFactoryMode)
        send(JBD.mosControl(charge: charge, discharge: discharge))
        send(JBD.closeFactoryMode)

        // The BMS answers the write, but the state we display comes from the next
        // basic-info poll — release the UI once that has had time to land.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pollInterval * 2) { [weak self] in
            self?.isWritingMOS = false
        }
    }

    // MARK: - Incoming frames

    private func handle(_ frame: [UInt8]) {
        do {
            let response = try JBD.decode(frame)
            guard response.isOK else {
                if response.register == JBD.Register.mosControl.rawValue {
                    lastError = "Le BMS a refusé la commande MOSFET (mot de passe ?)."
                }
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
            default:
                break
            }
        } catch {
            // A corrupt frame is not worth surfacing: the next poll is a second away.
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
            resetReadings()
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
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
            ?? "BMS inconnu"
        let device = DiscoveredBMS(id: peripheral.identifier,
                                   name: name,
                                   rssi: RSSI.intValue,
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
        lastError = error?.localizedDescription ?? "Connexion impossible."
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
            abortConnection("Service FF00 introuvable sur cet appareil.")
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
            abortConnection("Caractéristique d'écriture FF02 introuvable.")
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
