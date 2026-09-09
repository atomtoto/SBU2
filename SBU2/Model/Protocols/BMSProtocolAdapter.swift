//
//  BMSProtocolAdapter.swift
//  SBU2
//

import CoreBluetooth
import Foundation

/// The BMS families the app can talk to.
///
/// Only JBD is implemented today. Everything above the transport goes through
/// `BMSProtocolAdapter`, so adding a family means writing one adapter and listing its
/// descriptor in `BMSProtocolRegistry`: neither `BMSConnection` nor any view names a
/// protocol, a register or a frame layout.
enum BMSProtocolID: String, Codable, CaseIterable, Identifiable, Sendable {
    case jbd

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

    /// The reads issued on every polling tick, in the order they should go out.
    func pollCommands() -> [BMSCommand]

    /// The bracketed sequence that switches the MOSFETs. `password` is the hardware
    /// password to replay first, or `nil` on an unprotected pack.
    func mosCommands(charge: Bool, discharge: Bool, password: String?) -> [BMSCommand]

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
    /// Whether this family claims a peripheral, given what it advertises.
    var matches: (_ advertisement: [String: Any], _ name: String?) -> Bool
    var make: () -> any BMSProtocolAdapter
}

/// The families compiled into the app.
enum BMSProtocolRegistry {

    static let descriptors: [BMSProtocolDescriptor] = [JBDAdapter.descriptor]

    /// Used when nothing else matches, and as the type of any device stored before
    /// the app knew about more than one family.
    static var fallback: BMSProtocolDescriptor { JBDAdapter.descriptor }

    /// The services to scan for: every family's, listed once.
    static var scanServices: [CBUUID] {
        var services: [CBUUID] = []
        for descriptor in descriptors where !services.contains(descriptor.profile.service) {
            services.append(descriptor.profile.service)
        }
        return services
    }

    static func descriptor(for id: BMSProtocolID) -> BMSProtocolDescriptor {
        descriptors.first { $0.id == id } ?? fallback
    }

    /// The family a freshly discovered peripheral belongs to.
    static func descriptor(advertisement: [String: Any], name: String?) -> BMSProtocolDescriptor {
        descriptors.first { $0.matches(advertisement, name) } ?? fallback
    }
}
