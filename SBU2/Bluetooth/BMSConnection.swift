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
    /// The family this peripheral's advertisement matched.
    var protocolID: BMSProtocolID = .jbd

    fileprivate var peripheral: CBPeripheral?

    static func == (lhs: DiscoveredBMS, rhs: DiscoveredBMS) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Scans for BMS dongles, keeps one open and polls it for live values.
///
/// Commands leave the phone **one at a time**. The dongles are UART bridges with a
/// small buffer: a request written while the previous answer is still streaming
/// truncates it, and CoreBluetooth silently throws away a write-without-response
/// issued while its own send queue is full. SBU2 used to write the
/// basic-information request and the cell-voltage request back to back in the same
/// run-loop tick, which is why the first of the two — state of charge, MOSFET flags,
/// temperatures — was the reading that kept dropping out, and why it only worked
/// close to the pack, where the link is quick enough for the first answer to finish
/// before the second request lands. SBU never had the problem: it queued requests
/// and drained one every 150 ms. This does the same, and additionally waits for each
/// answer before writing the next command.
///
/// Nothing here names a register or a frame layout: `BMSProtocolAdapter` supplies the
/// commands and turns the answers back into events.
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

    /// How often a fresh round of readings is asked for.
    private static let pollInterval: TimeInterval = 1.0
    /// How often the outbox is drained. At most one command leaves per tick.
    private static let sendInterval: TimeInterval = 0.15
    /// How long a command holds the line while waiting for its answer.
    private static let responseTimeout: TimeInterval = 1.0
    /// A command is never given up on while bytes are still coming in — cutting in on
    /// an answer in progress is the very thing that used to truncate it.
    private static let quietBeforeGivingUp: TimeInterval = 0.3
    /// No byte at all for this long means the stream is out of step: drop what is
    /// buffered and start the conversation over.
    private static let stallTimeout: TimeInterval = 5.0
    /// Still nothing after that: the dongle is wedged and only a new link revives it.
    private static let relinkTimeout: TimeInterval = 12.0

    // MARK: Observable state

    private(set) var status: Status = .idle
    private(set) var discovered: [DiscoveredBMS] = []
    private(set) var info = BasicInfo()
    private(set) var cellVoltages: [Double] = []
    private(set) var lastUpdate: Date?
    private(set) var lastError: String?
    /// Tracks the MOSFET command currently waiting for the pack to confirm it.
    private(set) var mosWrite = MOSWriteTracker()
    private(set) var passwordOutcome: WriteOutcome = .idle
    /// The family the open device speaks.
    private(set) var protocolID: BMSProtocolID = .jbd

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

    var protocolLabel: String { descriptor.label }

    var supportsPasswordManagement: Bool { adapter.supportsPasswordManagement }

    func isValidPassword(_ password: String) -> Bool { adapter.isValidPassword(password) }

    // MARK: Internals

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var writeCharacteristic: CBCharacteristic?
    /// Set once the pack's notifications are actually subscribed. Requests written
    /// before that are answered into a void.
    @ObservationIgnored private var notifying = false
    @ObservationIgnored private var descriptor = BMSProtocolRegistry.fallback
    @ObservationIgnored private var adapter: any BMSProtocolAdapter = BMSProtocolRegistry.fallback.make()
    /// Commands waiting to be written, in order.
    @ObservationIgnored private var outbox: [BMSCommand] = []
    /// The command whose answer the transport is waiting for.
    @ObservationIgnored private var inFlight: BMSCommand?
    @ObservationIgnored private var inFlightSince: Date?
    /// When the pack last sent anything at all, complete frame or not. Used both to
    /// avoid interrupting an answer in progress and to notice a dead conversation.
    @ObservationIgnored private var lastNotificationAt: Date?
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var sendTimer: Timer?
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
        central.scanForPeripherals(withServices: BMSProtocolRegistry.scanServices)
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

        // A device remembers the family it was opened with; a new one takes whatever
        // its advertisement matched.
        protocolID = settings.protocolID ?? device.protocolID
        descriptor = BMSProtocolRegistry.descriptor(for: protocolID)
        adapter = descriptor.make()
        settings.protocolID = protocolID
        saveSettings()

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
        adapter.reset()
        info = BasicInfo()
        cellVoltages = []
        lastUpdate = nil
        mosWrite.cancel()
        writeCharacteristic = nil
        notifying = false
    }

    private func abortConnection(_ message: String) {
        lastError = message
        wantsConnection = false
        stopPolling()
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        } else {
            startScanning()
        }
    }

    // MARK: - Timers

    /// Timers added to the common run-loop modes.
    ///
    /// A plain `Timer.scheduledTimer` only runs in the default mode, so it stops
    /// firing for as long as a scroll view is being dragged — the readings froze
    /// mid-gesture and resumed when the finger came up. SBU added its timers to the
    /// common modes for exactly this reason.
    private func makeTimer(interval: TimeInterval, _ body: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in body() }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func startPolling() {
        stopPolling()
        lastNotificationAt = .now
        tick()
        pollTimer = makeTimer(interval: Self.pollInterval) { [weak self] in self?.tick() }
        if demo == nil {
            sendTimer = makeTimer(interval: Self.sendInterval) { [weak self] in self?.pumpOutbox() }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        sendTimer?.invalidate()
        sendTimer = nil
        outbox.removeAll()
        inFlight = nil
        inFlightSince = nil
    }

    /// One round: expire a stale MOSFET command, then ask for fresh readings.
    private func tick() {
        if mosWrite.expire() {
            lastError = "The BMS did not confirm the command within \(Int(MOSWriteTracker.timeout)) seconds."
        }

        guard demo == nil else {
            stepDemo()
            return
        }

        let silence = Date.now.timeIntervalSince(lastNotificationAt ?? .distantPast)
        if silence > Self.relinkTimeout, let peripheral {
            // Resetting the stream did not help, so the dongle itself has stopped
            // answering. `wantsConnection` is still set, so the disconnect handler
            // reconnects straight away.
            lastNotificationAt = .now
            central.cancelPeripheralConnection(peripheral)
            return
        }
        if silence > Self.stallTimeout {
            // Nothing has come back in a while. Whatever is half-received is never
            // going to complete, so drop it and start over.
            adapter.reset()
            outbox.removeAll()
            inFlight = nil
            inFlightSince = nil
        }

        enqueuePoll()
        pumpOutbox()
    }

    private func stepDemo() {
        demo?.step()
        info = demo?.info ?? BasicInfo()
        cellVoltages = demo?.cellVoltages ?? []
        lastUpdate = .now
        // The demo pack never answers a command, so reconcile the tracker here too.
        mosWrite.reconcile(chargeEnabled: info.chargeMOSEnabled,
                           dischargeEnabled: info.dischargeMOSEnabled)
    }

    // MARK: - Outbox

    /// Queues one round of reads, unless the previous round has not gone out yet.
    ///
    /// Skipping rather than appending is deliberate: on a weak link the queue would
    /// otherwise grow without bound and the screen would end up showing readings
    /// minutes old. It also keeps a write bracket contiguous — no read is ever
    /// inserted between the commands that open and close factory mode.
    private func enqueuePoll() {
        guard outbox.isEmpty else { return }
        outbox.append(contentsOf: adapter.pollCommands())
    }

    /// Queues a write bracket ahead of any pending reads.
    private func enqueueWrite(_ commands: [BMSCommand]) {
        guard !commands.isEmpty else { return }
        outbox.removeAll { $0.isPoll }
        outbox.append(contentsOf: commands)
        pumpOutbox()
    }

    /// Writes at most one command, and only when the line is free.
    private func pumpOutbox() {
        guard let peripheral, let writeCharacteristic,
              peripheral.state == .connected, notifying
        else { return }

        if inFlight != nil {
            guard let inFlightSince,
                  Date.now.timeIntervalSince(inFlightSince) >= Self.responseTimeout,
                  Date.now.timeIntervalSince(lastNotificationAt ?? .distantPast) >= Self.quietBeforeGivingUp
            else { return }
            // The pack never answered. Let the next command through rather than
            // holding the line for good.
            self.inFlight = nil
            self.inFlightSince = nil
        }

        guard !outbox.isEmpty else { return }

        let type = writeType(for: writeCharacteristic)
        // A write-without-response issued while CoreBluetooth's queue is full is
        // dropped without telling anyone; the callback below brings us back.
        if type == .withoutResponse, !peripheral.canSendWriteWithoutResponse { return }

        let command = outbox.removeFirst()
        peripheral.writeValue(Data(command.bytes), for: writeCharacteristic, type: type)
        if command.expectedRegister != nil {
            inFlight = command
            inFlightSince = .now
        }
    }

    /// Every dongle seen so far offers write-without-response; the fallback is there
    /// for the ones that do not.
    private func writeType(for characteristic: CBCharacteristic) -> CBCharacteristicWriteType {
        characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
    }

    /// The pack answered the command holding the line, so the next one may go out.
    private func retireInFlight(answering register: UInt8) {
        guard let expected = inFlight?.expectedRegister, expected == register else { return }
        inFlight = nil
        inFlightSince = nil
    }

    // MARK: - Writes

    var canControlMOS: Bool {
        status.isConnected && adapter.supportsMOSControl && settings.liontronMode != .autoEnabled
    }

    /// Sends a MOSFET command and waits for the pack to report the requested state.
    ///
    /// Nothing is sent while another command is unresolved: the BMS applies these
    /// inside a factory-mode bracket, and interleaving two of them is how you end up
    /// with a state neither the app nor the user asked for.
    func setMOS(terminal: MOSWriteTracker.Terminal, charge: Bool, discharge: Bool) {
        guard canControlMOS, !mosWrite.isBusy else { return }
        guard mosWrite.begin(terminal: terminal, charge: charge, discharge: discharge) else { return }
        lastError = nil

        if demo != nil {
            // The simulated pack has no radio, so apply the change on a short delay —
            // otherwise the spinner would never be visible on the demo device.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, self.demo != nil, self.mosWrite.isBusy else { return }
                self.demo?.setMOS(charge: charge, discharge: discharge)
            }
            return
        }

        enqueueWrite(adapter.mosCommands(charge: charge,
                                         discharge: discharge,
                                         password: replayPassword))
    }

    /// The password to replay before a write, or `nil` on an unprotected pack.
    private var replayPassword: String? {
        settings.hasPassword ? settings.password : nil
    }

    // MARK: - Hardware password

    func createPassword(_ new: String) {
        let commands = adapter.createPasswordCommands(new)
        guard !commands.isEmpty else { return }
        passwordOutcome = .idle
        enqueueWrite(commands)
        settings.password = new
        settings.hasPassword = true
        saveSettings()
    }

    func changePassword(to new: String) {
        let commands = adapter.changePasswordCommands(from: settings.password, to: new)
        guard !commands.isEmpty else { return }
        passwordOutcome = .idle
        enqueueWrite(commands)
        settings.password = new
        saveSettings()
    }

    func removePassword() {
        let commands = adapter.removePasswordCommands(current: settings.password)
        guard !commands.isEmpty else { return }
        passwordOutcome = .idle
        enqueueWrite(commands)
        settings.hasPassword = false
        settings.password = "000000"
        saveSettings()
    }

    // MARK: - Incoming events

    private func handle(_ event: BMSEvent) {
        retireInFlight(answering: event.register)

        switch event.kind {
        case .basicInfo(let decoded):
            info = decoded
            lastUpdate = .now
            mosWrite.reconcile(chargeEnabled: decoded.chargeMOSEnabled,
                               dischargeEnabled: decoded.dischargeMOSEnabled)
        case .cellVoltages(let voltages):
            cellVoltages = voltages
            lastUpdate = .now
        case .accepted:
            break
        case .passwordAccepted:
            passwordOutcome = .succeeded
        case .passwordRejected:
            passwordOutcome = .rejected("The BMS rejected the password.")
            settings.hasPassword = true
            saveSettings()
            abandonBracket()
        case .rejected(let hardwareLocked):
            mosWrite.cancel()
            abandonBracket()
            if hardwareLocked, settings.liontronMode == .autoDisabled {
                settings.liontronMode = .autoEnabled
                saveSettings()
            }
            lastError = settings.hasPassword
                ? "The BMS rejected the command. Check the password."
                : "The BMS rejected the command. This pack may be hardware locked."
        }
    }

    /// Drops the rest of a refused write bracket, but keeps the command that closes
    /// factory mode so the pack is not left open.
    private func abandonBracket() {
        outbox.removeAll { !$0.isPoll && !$0.isCleanup }
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
            ?? "Unknown BMS"
        let family = BMSProtocolRegistry.descriptor(advertisement: advertisementData, name: advertised)
        let device = DiscoveredBMS(id: peripheral.identifier.uuidString,
                                   name: advertised,
                                   rssi: RSSI.intValue,
                                   isDemo: false,
                                   protocolID: family.id,
                                   peripheral: peripheral)

        if let index = discovered.firstIndex(where: { $0.id == device.id }) {
            discovered[index] = device
        } else {
            discovered.append(device)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        adapter.reset()
        notifying = false
        peripheral.discoverServices([descriptor.profile.service])
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
        let profile = descriptor.profile
        guard let service = peripheral.services?.first(where: { $0.uuid == profile.service }) else {
            abortConnection("Service \(profile.service.uuidString) not found on this device.")
            return
        }
        peripheral.discoverCharacteristics([profile.notify, profile.write], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        let profile = descriptor.profile
        var notifyCharacteristic: CBCharacteristic?

        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case profile.notify:
                notifyCharacteristic = characteristic
            case profile.write:
                writeCharacteristic = characteristic
            default:
                break
            }
        }

        guard writeCharacteristic != nil else {
            abortConnection("Write characteristic \(profile.write.uuidString) not found.")
            return
        }
        guard let notifyCharacteristic else {
            abortConnection("Notify characteristic \(profile.notify.uuidString) not found.")
            return
        }
        // Polling starts from didUpdateNotificationStateFor, once the subscription is
        // live: anything written before that is answered to nobody.
        peripheral.setNotifyValue(true, for: notifyCharacteristic)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == descriptor.profile.notify else { return }
        if let error {
            abortConnection(error.localizedDescription)
            return
        }
        notifying = characteristic.isNotifying
        guard notifying else { return }
        status = .connected(peripheral.name ?? "BMS")
        startPolling()
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard error == nil, let data = characteristic.value, !data.isEmpty else { return }
        lastNotificationAt = .now
        for event in adapter.ingest(data) {
            handle(event)
        }
    }

    /// CoreBluetooth's send queue has room again — a command held back by
    /// `canSendWriteWithoutResponse` can go out now instead of waiting for the tick.
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        pumpOutbox()
    }
}
