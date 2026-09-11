//
//  JKAdapter.swift
//  SBU2
//

import CoreBluetooth
import Foundation

/// Talks to JK (Jikong) packs.
///
/// Reading only, for now. Every write this protocol offers goes into the pack's
/// settings — cell count, capacity, protection thresholds, the MOSFET switches —
/// and none of it can be tried from here against real hardware, so none of it is
/// offered: `supports…` is false across the board and every write method returns
/// nothing. The charge and discharge buttons still show what the pack is doing;
/// they just will not change it.
final class JKAdapter: BMSProtocolAdapter {

    private static let serviceUUID = CBUUID(string: "FFE0")
    /// One characteristic carries both directions, unlike JBD's pair.
    private static let characteristicUUID = CBUUID(string: "FFE1")

    static let descriptor = BMSProtocolDescriptor(
        id: .jk,
        label: "JK / Jikong",
        profile: BMSGATTProfile(service: JKAdapter.serviceUUID,
                                notify: JKAdapter.characteristicUUID,
                                write: JKAdapter.characteristicUUID),
        // A JK pack is recognised three ways, because which of them a given module
        // offers varies: by the service it advertises, by the service it lists only
        // in its scan response (iOS reports those separately, under the overflow
        // key), or by a name beginning "JK", which every one of them uses. Any one is
        // enough — a module that advertises nothing but its name is still findable.
        matches: { advertisement, name in
            if let name, name.uppercased().hasPrefix("JK") { return true }
            let keys = [CBAdvertisementDataServiceUUIDsKey,
                        CBAdvertisementDataOverflowServiceUUIDsKey,
                        CBAdvertisementDataSolicitedServiceUUIDsKey]
            return keys.contains { key in
                (advertisement[key] as? [CBUUID])?.contains(JKAdapter.serviceUUID) ?? false
            }
        },
        make: { JKAdapter() })

    private var assembler = JKFrameAssembler()
    /// Settled on the first frame that makes sense as one layout and not the other,
    /// then left alone: a pack does not change shape mid-session, and re-deciding on
    /// every frame would let one bad frame flip the whole screen.
    private var variant: JK.Variant?
    /// What the pack said about itself. Also the flag for whether to keep asking.
    private var identity: JK.Identity?

    var supportsMOSControl: Bool { false }
    var supportsPasswordManagement: Bool { false }
    var supportsClearingAlerts: Bool { false }
    var supportsCalibration: Bool { false }

    // MARK: - Commands

    /// The pack is asked who it is until it says, and for its readings every time.
    ///
    /// JK will also stream readings unprompted once asked the first time. Asking
    /// again each round is harmless — it answers either way — and it keeps this
    /// family on the same footing as JBD, where a round that goes unanswered is what
    /// tells the transport the link has gone quiet.
    func pollCommands() -> [BMSCommand] {
        var commands: [BMSCommand] = []
        if identity == nil {
            commands.append(poll(.deviceInfo))
        }
        commands.append(poll(.cellInfo))
        return commands
    }

    private func poll(_ command: JK.Command) -> BMSCommand {
        BMSCommand(bytes: JK.request(command),
                   expectedRegister: command.answers.rawValue,
                   isPoll: true)
    }

    // MARK: - Writes, none of which this family offers yet

    func mosCommands(charge: Bool, discharge: Bool, password: String?) -> [BMSCommand] { [] }
    func clearAlertsCommands(password: String?) -> [BMSCommand] { [] }
    func calibrationCommands(_ calibration: BMSCalibration, password: String?) -> [BMSCommand] { [] }
    func createPasswordCommands(_ new: String) -> [BMSCommand] { [] }
    func changePasswordCommands(from current: String, to new: String) -> [BMSCommand] { [] }
    func removePasswordCommands(current: String) -> [BMSCommand] { [] }
    func isValidPassword(_ password: String) -> Bool { false }

    // MARK: - Answers

    func reset() {
        assembler.reset()
    }

    func ingest(_ data: Data) -> [BMSEvent] {
        assembler.append(data).flatMap(events(for:))
    }

    private func events(for frame: [UInt8]) -> [BMSEvent] {
        guard frame.count > 4, let type = JK.FrameType(rawValue: frame[4]) else { return [] }

        switch type {
        case .deviceInfo:
            guard let decoded = JK.decodeDeviceInfo(frame) else { return [] }
            identity = decoded
            // Nothing to show on its own — it is folded into the next reading — but
            // the transport still needs to hear that the request was answered.
            return [BMSEvent(register: type.rawValue, kind: .accepted)]

        case .cellInfo:
            if variant == nil { variant = JK.variant(ofCellInfo: frame) }
            guard let variant, var info = JK.decodeCellInfo(frame, variant) else { return [] }
            // The version and the build date live in the other frame, so they are
            // carried across rather than left blank on every reading.
            info.softwareVersion = identity?.softwareVersion ?? ""
            info.productionDate = identity?.productionDate
            return [BMSEvent(register: type.rawValue, kind: .basicInfo(info)),
                    BMSEvent(register: type.rawValue,
                             kind: .cellVoltages(JK.cellVoltages(frame, variant)))]

        case .settings:
            // Thresholds and limits. Nothing reads them yet.
            return []
        }
    }
}
