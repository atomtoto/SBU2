//
//  BMSProtocolAdapter.swift
//  SBU2
//

import CoreBluetooth
import Foundation

/// The BMS families the app can talk to.
///
/// Everything above the transport goes through `BMSProtocolAdapter`, so adding a
/// family means writing one adapter and listing its descriptor in
/// `BMSProtocolRegistry`: neither `BMSConnection` nor any view names a protocol, a
/// register or a frame layout. JK proved that out — it shares nothing with JBD but
/// the shape of the adapter, down to the byte order.
enum BMSProtocolID: String, Codable, CaseIterable, Identifiable, Sendable {
    case jbd
    case jk

    var id: Self { self }
}

/// The GATT profile a family uses: one service carrying a notify and a write
/// characteristic.
struct BMSGATTProfile: Equatable {
    var service: CBUUID
    var notify: CBUUID
    var write: CBUUID
}

/// One byte string to write, and what to expect back.
struct BMSCommand: Equatable {
    var bytes: [UInt8]
    /// The register the pack echoes when it answers this command, or `nil` when it
    /// answers nothing. The transport holds the line until that answer arrives — or
    /// until the deadline passes — before writing the next command.
    var expectedRegister: UInt8?
    /// A periodic read. A round is skipped rather than queued twice when the link is
    /// slow, so a bad connection cannot build a backlog of stale requests.
    var isPoll = false
    /// Closes a bracket the preceding commands opened. It is still sent when one of
    /// them is refused, so a rejection cannot leave the pack in factory mode.
    var isCleanup = false
}

/// One calibration the user has asked for.
///
/// Each carries the *true* figure, measured with something trustworthy: the pack is
/// told what it should be reading and works out its own correction. The ranges are
/// sanity limits rather than protocol limits — they exist so a mistyped figure is
/// refused here instead of quietly landing in the pack's EEPROM.
enum BMSCalibration: Equatable {
    /// The measured voltage at one cell's terminals, in millivolts.
    case cell(index: Int, millivolts: Int)
    /// The measured temperature at one sensor, in degrees Celsius.
    case temperature(index: Int, celsius: Double)
    /// Zeroes the current reading. Nothing may be flowing when this is sent.
    case idleCurrent
    /// The measured current now flowing, in amps, as a magnitude.
    case chargeCurrent(amperes: Double)
    case dischargeCurrent(amperes: Double)

    static let millivoltRange = 500...5000
    static let celsiusRange = -40.0...125.0
    /// The upper end is what a signed 16-bit register in hundredths of an amp holds.
    static let ampereRange = 0.1...327.0

    var isPlausible: Bool {
        switch self {
        case .cell(_, let millivolts):
            Self.millivoltRange.contains(millivolts)
        case .temperature(_, let celsius):
            Self.celsiusRange.contains(celsius)
        case .idleCurrent:
            true
        case .chargeCurrent(let amperes), .dischargeCurrent(let amperes):
            Self.ampereRange.contains(abs(amperes))
        }
    }

    /// Whether the pack has to be told to commit this one to EEPROM on the way out.
    /// Only the current gain does; the rest the firmware keeps by itself.
    var savesToEEPROM: Bool {
        switch self {
        case .chargeCurrent, .dischargeCurrent: true
        case .cell, .temperature, .idleCurrent: false
        }
    }
}

/// What an adapter understood in the incoming byte stream.
struct BMSEvent: Equatable {

    enum Kind: Equatable {
        case basicInfo(BasicInfo)
        case cellVoltages([Double])
        /// A write the pack acknowledged.
        case accepted
        /// A write the pack refused.
        case rejected
        case passwordAccepted
        case passwordRejected
    }

    /// The register the pack answered, so the transport knows which command is done.
    var register: UInt8
    var kind: Kind
}

/// Everything `BMSConnection` needs in order to talk to one family of BMS.
///
/// An adapter is stateful — it owns the reassembly buffer for its own framing — and
/// lives for as long as one device stays open.
protocol BMSProtocolAdapter: AnyObject {

    var supportsMOSControl: Bool { get }
    var supportsPasswordManagement: Bool { get }
    /// Whether the family can wipe the fault records the pack has stored.
    var supportsClearingAlerts: Bool { get }
    /// Whether the family can be told what its readings should really be.
    var supportsCalibration: Bool { get }

    /// The reads issued on every polling tick, in the order they should go out.
    func pollCommands() -> [BMSCommand]

    /// The bracketed sequence that switches the MOSFETs. `password` is the hardware
    /// password to replay first, or `nil` on an unprotected pack.
    ///
    /// `charge` and `discharge` are the state the pack should end up in; `terminal`
    /// is the one the user actually touched. A family that carries both terminals in
    /// a single write ignores the third argument, and one that keeps a register per
    /// terminal uses it to leave the other register alone.
    func mosCommands(terminal: MOSWriteTracker.Terminal,
                     charge: Bool,
                     discharge: Bool,
                     password: String?) -> [BMSCommand]

    /// The bracketed sequence that clears the pack's stored alerts. Empty when the
    /// family cannot do it. `password` replays as it does for `mosCommands`.
    func clearAlertsCommands(password: String?) -> [BMSCommand]

    /// The bracketed sequence that applies one calibration. Empty when the family
    /// cannot do it, or when the figure is outside `BMSCalibration`'s sanity range.
    func calibrationCommands(_ calibration: BMSCalibration, password: String?) -> [BMSCommand]

    /// Empty when the family cannot do this, or when the password is malformed.
    func createPasswordCommands(_ new: String) -> [BMSCommand]
    func changePasswordCommands(from current: String, to new: String) -> [BMSCommand]
    func removePasswordCommands(current: String) -> [BMSCommand]
    func isValidPassword(_ password: String) -> Bool

    /// Drops anything half-received. Called whenever the link is (re)established and
    /// whenever the stream is suspected of having gone out of step.
    func reset()

    /// Feeds one notification in and returns everything it completed.
    func ingest(_ data: Data) -> [BMSEvent]
}

/// How the app finds, recognises and instantiates one family.
struct BMSProtocolDescriptor {
    var id: BMSProtocolID
    var label: String
    var profile: BMSGATTProfile
    /// Whether this family recognises a peripheral from what it advertises.
    ///
    /// This has to be a *positive* identification and never a catch-all: the scan no
    /// longer filters on service, so everything within radio range is offered here,
    /// and a matcher that says yes to anything would fill the device list with
    /// headphones.
    var matches: (_ advertisement: [String: Any], _ name: String?) -> Bool
    var make: () -> any BMSProtocolAdapter
}

/// The families compiled into the app.
enum BMSProtocolRegistry {

    /// JK first: its matcher is the strict one, and JBD's deliberately claims any
    /// peripheral whose advertisement lists no services at all. With JBD first, a JK
    /// pack that advertised nothing would be opened as a JBD one and answer nothing.
    static let descriptors: [BMSProtocolDescriptor] = [JKAdapter.descriptor, JBDAdapter.descriptor]

    /// Used when nothing else matches, and as the type of any device stored before
    /// the app knew about more than one family.
    static var fallback: BMSProtocolDescriptor { JBDAdapter.descriptor }

    /// The services that identify a family, listed once. Not a scan filter any more —
    /// see `BMSConnection.startScanning` for why — but still what a peripheral is
    /// recognised by.
    static var identifyingServices: [CBUUID] {
        var services: [CBUUID] = []
        for descriptor in descriptors where !services.contains(descriptor.profile.service) {
            services.append(descriptor.profile.service)
        }
        return services
    }

    static func descriptor(for id: BMSProtocolID) -> BMSProtocolDescriptor {
        descriptors.first { $0.id == id } ?? fallback
    }

    /// The family a peripheral belongs to, or `nil` if it is not one of ours.
    ///
    /// Answering `nil` is the point: discovery shows a device only when some family
    /// recognises it, so this is what keeps every other BLE device in the building
    /// out of the list.
    static func match(advertisement: [String: Any], name: String?) -> BMSProtocolDescriptor? {
        descriptors.first { $0.matches(advertisement, name) }
    }

    /// The family a freshly discovered peripheral belongs to, falling back rather
    /// than refusing. For callers that have to name one either way.
    static func descriptor(advertisement: [String: Any], name: String?) -> BMSProtocolDescriptor {
        match(advertisement: advertisement, name: name) ?? fallback
    }
}
