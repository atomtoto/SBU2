//
//  JKAdapter.swift
//  SBU2
//

import CoreBluetooth
import Foundation

/// Talks to JK (Jikong) packs.
///
/// The two terminals can be switched. Nothing else is written: the rest of what this
/// protocol offers is stored settings — cell count, capacity, protection thresholds
/// — and those stay off the table for now.
///
/// No password is sent with a write, because the protocol has nowhere to put one.
/// The reference implementation writes these same two registers with no
/// authentication of any kind, and there is no login or unlock frame anywhere in it.
/// What the pack does carry is its own passcode, in plain text, in the frame it sends
/// when asked who it is — which is what an app would read in order to check a
/// password *itself* before writing. So a password prompt is a gate the app puts in
/// front of the user, not something the BMS demands.
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
    /// When the last reading came in, which is what says whether the pack is still
    /// streaming or has gone quiet and needs asking again.
    private var lastCellInfo: Date?
    /// Injectable so the asking-again rule can be tested without waiting for it.
    var now: () -> Date = Date.init

    var supportsMOSControl: Bool { true }
    var supportsPasswordManagement: Bool { false }
    var supportsClearingAlerts: Bool { false }
    var supportsCalibration: Bool { false }

    // MARK: - Commands

    /// Asked once, then left alone.
    ///
    /// A JK pack is not polled the way a JBD one is. Asked once for its readings it
    /// streams them from then on, so asking again every second buys nothing — and it
    /// is not free: the pack beeps at every command it receives, so a poll a second
    /// is a beep a second, which is what a JK pack sounded like until this stopped
    /// doing it. The reference implementation stops asking the moment the first
    /// reading lands, and so does this.
    ///
    /// Asking resumes if the stream dries up, which is what makes it safe to stop.
    func pollCommands() -> [BMSCommand] {
        var commands: [BMSCommand] = []
        if identity == nil, !askedRecently(.deviceInfo) {
            commands.append(poll(.deviceInfo))
        }
        if isStreamStale, !askedRecently(.cellInfo) {
            commands.append(poll(.cellInfo))
        }
        return commands
    }

    /// Long enough that a pack streaming at its own pace is never interrupted, short
    /// enough that a stream which stops is noticed before the screen goes stale.
    private static let streamTimeout: TimeInterval = 4

    private var isStreamStale: Bool {
        guard let lastCellInfo else { return true }
        return now().timeIntervalSince(lastCellInfo) > Self.streamTimeout
    }

    /// What was asked and when, so a pack that answers nothing is asked again at the
    /// same unhurried pace rather than once a second. Going unanswered is exactly the
    /// case where the beeping would otherwise come back.
    private var lastAsked: [JK.Command: Date] = [:]

    private func askedRecently(_ command: JK.Command) -> Bool {
        guard let asked = lastAsked[command] else { return false }
        return now().timeIntervalSince(asked) <= Self.streamTimeout
    }

    private func poll(_ command: JK.Command) -> BMSCommand {
        lastAsked[command] = now()
        return BMSCommand(bytes: JK.request(command),
                          expectedRegister: command.answers.rawValue,
                          isPoll: true)
    }

    // MARK: - Writes

    /// Both terminals, one register each.
    ///
    /// JK keeps them apart where JBD packs both into a single write, so the one that
    /// did not change is written back at the value it already holds. That is a no-op
    /// to the pack, and it keeps this the same one-call operation it is everywhere
    /// else in the app.
    ///
    /// Nothing is expected back. The pack does not acknowledge a register write, and
    /// it does not need to: it is already streaming readings, and the next one says
    /// whether the terminal moved — which is the confirmation the button waits on.
    func mosCommands(charge: Bool, discharge: Bool, password: String?) -> [BMSCommand] {
        [BMSCommand(bytes: JK.write(.chargingSwitch, on: charge)),
         BMSCommand(bytes: JK.write(.dischargingSwitch, on: discharge))]
    }

    func clearAlertsCommands(password: String?) -> [BMSCommand] { [] }
    func calibrationCommands(_ calibration: BMSCalibration, password: String?) -> [BMSCommand] { [] }
    func createPasswordCommands(_ new: String) -> [BMSCommand] { [] }
    func changePasswordCommands(from current: String, to new: String) -> [BMSCommand] { [] }
    func removePasswordCommands(current: String) -> [BMSCommand] { [] }
    func isValidPassword(_ password: String) -> Bool { false }

    // MARK: - Answers

    func reset() {
        assembler.reset()
        // Whatever was streaming is not any more, so the pack gets asked again — and
        // asked straight away rather than after the usual wait.
        lastCellInfo = nil
        lastAsked.removeAll()
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
            // Detection is retried until a frame settles it, but never gates the
            // reading: a pack whose average-cell field reads zero would otherwise
            // decode to nothing at all, and a screen that stays empty says far less
            // than one whose figures can be seen to be wrong. The short layout stands
            // in meanwhile, which is what the reference defaults to anyway.
            if variant == nil { variant = JK.variant(ofCellInfo: frame) }
            let layout = variant ?? .cells24
            guard var info = JK.decodeCellInfo(frame, layout) else { return [] }
            // The pack is talking, so it does not need asking again.
            lastCellInfo = now()
            // The version and the build date live in the other frame, so they are
            // carried across rather than left blank on every reading.
            info.softwareVersion = identity?.softwareVersion ?? ""
            info.productionDate = identity?.productionDate
            return [BMSEvent(register: type.rawValue, kind: .basicInfo(info)),
                    BMSEvent(register: type.rawValue,
                             kind: .cellVoltages(JK.cellVoltages(frame, layout)))]

        case .settings:
            // Thresholds and limits. Nothing reads them yet.
            return []
        }
    }
}
