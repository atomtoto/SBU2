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
        // This used to answer yes to an advertisement that named no service at all,
        // which was safe only while the scan itself filtered on FF00 — everything
        // reaching it was already a JBD. The scan no longer filters, so that same
        // answer would now claim every BLE device in radio range, and a JK pack that
        // advertises no service would be opened as a JBD one and answer nothing.
        //
        // Nothing is lost by being strict: the old filtered scan required FF00 in the
        // advertisement to see the device in the first place, so requiring it here
        // finds exactly the same dongles. iOS folds scan-response services into the
        // same key, so a dongle that answers with them rather than advertising them
        // still arrives with FF00 listed.
        matches: { advertisement, _ in
            guard let advertised = advertisement[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
            else { return false }
            return advertised.contains(JBDAdapter.serviceUUID)
        },
        make: { JBDAdapter() })

    private var assembler = FrameAssembler(layout: JBD.frameLayout)

    var supportsMOSControl: Bool { true }
    var supportsPasswordManagement: Bool { true }
    var supportsClearingAlerts: Bool { true }
    var supportsCalibration: Bool { true }

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

    /// Unlock if the pack is protected, open factory mode, then clear on the way out.
    ///
    /// The clearing write doubles as the one that leaves factory mode, so it carries
    /// `isCleanup` for the same reason `closeFactoryMode` does: a pack whose
    /// factory-mode open was refused must not be left waiting with it open.
    func clearAlertsCommands(password: String?) -> [BMSCommand] {
        unlockCommands(password)
            + [command(JBD.openFactoryMode, .factoryModeOpen), saveAndCloseFactoryMode]
    }

    /// Unlock if the pack is protected, open factory mode, hand over the true figure,
    /// then leave.
    ///
    /// Whether that last step commits the EEPROM follows the reference
    /// implementation exactly: the current *gain* is saved, while the per-cell,
    /// per-sensor and zero-current corrections are not — those the firmware keeps on
    /// its own. Committing where it does not is not a free extra safety net; it is a
    /// different command, and this is not the place to improvise.
    func calibrationCommands(_ calibration: BMSCalibration, password: String?) -> [BMSCommand] {
        guard calibration.isPlausible, let write = writeBytes(for: calibration) else { return [] }
        return unlockCommands(password)
            + [command(JBD.openFactoryMode, .factoryModeOpen),
               // The calibration registers are not in `JBD.Register`: they are a
               // block of addresses, and each answers on its own.
               BMSCommand(bytes: write, expectedRegister: write[JBD.registerIndex]),
               calibration.savesToEEPROM ? saveAndCloseFactoryMode : closeFactoryMode]
    }

    private func writeBytes(for calibration: BMSCalibration) -> [UInt8]? {
        switch calibration {
        case .cell(let index, let millivolts):
            JBD.calibrateCell(index: index, millivolts: millivolts)
        case .temperature(let index, let celsius):
            JBD.calibrateTemperature(index: index, celsius: celsius)
        case .idleCurrent:
            JBD.calibrateIdleCurrent
        case .chargeCurrent(let amperes):
            JBD.calibrateCurrent(charging: true, amperes: amperes)
        case .dischargeCurrent(let amperes):
            JBD.calibrateCurrent(charging: false, amperes: amperes)
        }
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

    /// Both of these end a bracket, so both carry `isCleanup`: a pack whose
    /// factory-mode open was refused must not be left waiting with it open.
    private var closeFactoryMode: BMSCommand {
        BMSCommand(bytes: JBD.closeFactoryMode,
                   expectedRegister: JBD.Register.factoryModeClose.rawValue,
                   isCleanup: true)
    }

    private var saveAndCloseFactoryMode: BMSCommand {
        BMSCommand(bytes: JBD.saveAndCloseFactoryMode,
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
            default:
                return BMSEvent(register: register, kind: .rejected)
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
