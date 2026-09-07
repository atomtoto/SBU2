//
//  JBDAdapter.swift
//  SBU2
//

import CoreBluetooth
import Foundation

/// Talks to JBD packs — the same firmware sold as Xiaoxiang, Overkill Solar and
/// LLT Power.
///
/// The wire format itself lives in `JBD`; this only says which commands make up a
/// poll or a write bracket, and turns answers into `BMSEvent`s.
final class JBDAdapter: BMSProtocolAdapter {

    private static let serviceUUID = CBUUID(string: "FF00")

    static let descriptor = BMSProtocolDescriptor(
        id: .jbd,
        label: "JBD / Xiaoxiang",
        profile: BMSGATTProfile(service: JBDAdapter.serviceUUID,
                                notify: CBUUID(string: "FF01"),
                                write: CBUUID(string: "FF02")),
        // The scan already filters on FF00, but a dongle is free to put its service
        // list in the scan response rather than the advertisement, so an
        // advertisement that names no service still counts as a match.
        matches: { advertisement, _ in
            guard let advertised = advertisement[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
                  !advertised.isEmpty
            else { return true }
            return advertised.contains(JBDAdapter.serviceUUID)
        },
        make: { JBDAdapter() })

    private var assembler = FrameAssembler(layout: JBD.frameLayout)

    var supportsMOSControl: Bool { true }
    var supportsPasswordManagement: Bool { true }

    // MARK: - Commands

    func pollCommands() -> [BMSCommand] {
        [command(JBD.readRequest(.basicInfo), .basicInfo, isPoll: true),
         command(JBD.readRequest(.cellVoltages), .cellVoltages, isPoll: true)]
    }

    /// Unlock the pack if it is protected, open factory mode, write, close it again.
    func mosCommands(charge: Bool, discharge: Bool, password: String?) -> [BMSCommand] {
        unlockCommands(password)
            + [command(JBD.openFactoryMode, .factoryModeOpen),
               command(JBD.mosControl(charge: charge, discharge: discharge), .mosControl),
               closeFactoryMode]
    }

    func createPasswordCommands(_ new: String) -> [BMSCommand] {
        guard let write = JBD.createPassword(new) else { return [] }
        return [command(JBD.openFactoryMode, .factoryModeOpen),
                command(write, .setPassword),
                closeFactoryMode]
    }

    func changePasswordCommands(from current: String, to new: String) -> [BMSCommand] {
        guard let write = JBD.changePassword(from: current, to: new) else { return [] }
        return unlockCommands(current)
            + [command(JBD.openFactoryMode, .factoryModeOpen),
               command(write, .setPassword),
               closeFactoryMode]
    }

    func removePasswordCommands(current: String) -> [BMSCommand] {
        guard JBD.isValidPassword(current) else { return [] }
        return unlockCommands(current)
            + [command(JBD.openFactoryMode, .factoryModeOpen),
               command(JBD.clearPassword, .clearPassword),
               closeFactoryMode]
    }

    func isValidPassword(_ password: String) -> Bool {
        JBD.isValidPassword(password)
    }

    private var closeFactoryMode: BMSCommand {
        BMSCommand(bytes: JBD.closeFactoryMode,
                   expectedRegister: JBD.Register.factoryModeClose.rawValue,
                   isCleanup: true)
    }

    private func command(_ bytes: [UInt8], _ register: JBD.Register, isPoll: Bool = false) -> BMSCommand {
        BMSCommand(bytes: bytes, expectedRegister: register.rawValue, isPoll: isPoll)
    }

    private func unlockCommands(_ password: String?) -> [BMSCommand] {
        guard let password, let bytes = JBD.enterPassword(password) else { return [] }
        return [command(bytes, .enterPassword)]
    }

    // MARK: - Answers

    func reset() {
        assembler.reset()
    }

    func ingest(_ data: Data) -> [BMSEvent] {
        assembler.append(data).compactMap(event(for:))
    }

    private func event(for frame: [UInt8]) -> BMSEvent? {
        guard let response = try? JBD.decode(frame) else { return nil }
        let register = response.register

        guard response.isOK else {
            switch register {
            case JBD.Register.enterPassword.rawValue,
                 JBD.Register.setPassword.rawValue,
                 JBD.Register.clearPassword.rawValue:
                return BMSEvent(register: register, kind: .passwordRejected)
            case JBD.Register.factoryModeOpen.rawValue, JBD.Register.mosControl.rawValue:
                // 0x80 on a factory-mode write is how a hardware-locked Liontron pack
                // answers.
                return BMSEvent(register: register,
                                kind: .rejected(hardwareLocked: response.status == 0x80))
            default:
                return BMSEvent(register: register, kind: .rejected(hardwareLocked: false))
            }
        }

        switch register {
        case JBD.Register.basicInfo.rawValue:
            guard let info = BasicInfo.decode(payload: response.payload) else { return nil }
            return BMSEvent(register: register, kind: .basicInfo(info))
        case JBD.Register.cellVoltages.rawValue:
            return BMSEvent(register: register,
                            kind: .cellVoltages(CellVoltages.decode(payload: response.payload)))
        case JBD.Register.enterPassword.rawValue,
             JBD.Register.setPassword.rawValue,
             JBD.Register.clearPassword.rawValue:
            return BMSEvent(register: register, kind: .passwordAccepted)
        default:
            return BMSEvent(register: register, kind: .accepted)
        }
    }
}
