//
//  MOSWriteTracker.swift
//  SBU2
//

import Foundation

/// Tracks a MOSFET command from the moment it is sent until the BMS confirms it,
/// rejects it, or stops answering.
///
/// The BMS has no acknowledgement that carries the new state, so a write is only
/// considered done once a later basic-information frame reports the state that was
/// asked for. Until then the button shows a spinner and no further command is sent.
struct MOSWriteTracker: Equatable {

    /// Which button the user pressed, so only that one spins.
    enum Terminal: Equatable {
        case charge
        case discharge
    }

    struct Request: Equatable {
        var terminal: Terminal
        /// The state the pack should be in once the BMS has applied the command.
        var charge: Bool
        var discharge: Bool
        var sentAt: Date
    }

    /// How long to wait for the pack to report the requested state before giving up.
    static let timeout: TimeInterval = 10

    private(set) var request: Request?

    var isBusy: Bool { request != nil }

    /// True while this specific button is waiting for its answer.
    func isWaiting(for terminal: Terminal) -> Bool {
        request?.terminal == terminal
    }

    /// Registers a command. Returns `false` when one is already in flight, so a second
    /// tap cannot queue a conflicting write while the first is unresolved.
    @discardableResult
    mutating func begin(terminal: Terminal, charge: Bool, discharge: Bool, at now: Date = .now) -> Bool {
        guard request == nil else { return false }
        request = Request(terminal: terminal, charge: charge, discharge: discharge, sentAt: now)
        return true
    }

    /// Clears the request once the pack reports the state that was asked for.
    /// Returns `true` when that just happened.
    @discardableResult
    mutating func reconcile(chargeEnabled: Bool, dischargeEnabled: Bool) -> Bool {
        guard let request else { return false }
        guard request.charge == chargeEnabled, request.discharge == dischargeEnabled else { return false }
        self.request = nil
        return true
    }

    /// Gives up on a command the pack never confirmed. Returns `true` when that just
    /// happened, so the caller can surface the failure once and only once.
    @discardableResult
    mutating func expire(now: Date = .now, timeout: TimeInterval = MOSWriteTracker.timeout) -> Bool {
        guard let request, now.timeIntervalSince(request.sentAt) >= timeout else { return false }
        self.request = nil
        return true
    }

    /// Drops the request without reporting anything — used when the BMS answers with an
    /// explicit error, and when the link goes away.
    mutating func cancel() {
        request = nil
    }
}
