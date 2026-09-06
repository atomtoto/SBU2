//
//  MOSWriteTrackerTests.swift
//  SBU2Tests
//

import Foundation
import Testing
@testable import SBU2

/// The `#expect` macro lifts its sub-expressions into closures whose captures are
/// immutable, so every mutating call is made on its own line and only the result is
/// handed to the macro.
@Suite("MOSFET command tracking")
struct MOSWriteTrackerTests {

    private let start = Date(timeIntervalSince1970: 1_000)

    @Test("A command marks only its own button as waiting")
    func onlyTheTappedButtonSpins() {
        var tracker = MOSWriteTracker()
        tracker.begin(terminal: .charge, charge: false, discharge: true, at: start)

        #expect(tracker.isBusy)
        #expect(tracker.isWaiting(for: .charge))
        #expect(!tracker.isWaiting(for: .discharge))
    }

    @Test("A second tap is refused while a command is unresolved")
    func secondTapRefused() {
        var tracker = MOSWriteTracker()
        let first = tracker.begin(terminal: .charge, charge: false, discharge: true, at: start)
        let second = tracker.begin(terminal: .discharge, charge: false, discharge: false, at: start)

        #expect(first)
        #expect(!second)
        // The first request is untouched, so the wrong write cannot be sent.
        #expect(tracker.isWaiting(for: .charge))
        #expect(tracker.request?.discharge == true)
    }

    @Test("The wait ends when the pack reports the requested state")
    func reconcilesOnMatchingState() {
        var tracker = MOSWriteTracker()
        tracker.begin(terminal: .charge, charge: false, discharge: true, at: start)
        let resolved = tracker.reconcile(chargeEnabled: false, dischargeEnabled: true)

        #expect(resolved)
        #expect(!tracker.isBusy)
    }

    @Test("A frame that still shows the old state keeps the spinner running")
    func staleFrameDoesNotResolve() {
        var tracker = MOSWriteTracker()
        tracker.begin(terminal: .charge, charge: false, discharge: true, at: start)
        let resolved = tracker.reconcile(chargeEnabled: true, dischargeEnabled: true)

        #expect(!resolved)
        #expect(tracker.isWaiting(for: .charge))
    }

    @Test("A frame where the other terminal also moved does not resolve")
    func partialMatchDoesNotResolve() {
        var tracker = MOSWriteTracker()
        tracker.begin(terminal: .charge, charge: false, discharge: true, at: start)
        let resolved = tracker.reconcile(chargeEnabled: false, dischargeEnabled: false)

        #expect(!resolved)
        #expect(tracker.isBusy)
    }

    @Test("Reconciling with no command in flight reports nothing")
    func reconcileWhenIdle() {
        var tracker = MOSWriteTracker()
        let resolved = tracker.reconcile(chargeEnabled: true, dischargeEnabled: true)

        #expect(!resolved)
    }

    @Test("The command expires once the deadline passes")
    func expiresAfterTimeout() {
        var tracker = MOSWriteTracker()
        tracker.begin(terminal: .discharge, charge: true, discharge: false, at: start)

        let early = tracker.expire(now: start.addingTimeInterval(9.9))
        #expect(!early)
        #expect(tracker.isBusy)

        let onDeadline = tracker.expire(now: start.addingTimeInterval(10))
        #expect(onDeadline)
        #expect(!tracker.isBusy)
    }

    @Test("Expiry is reported once, so the error is surfaced a single time")
    func expiresOnlyOnce() {
        var tracker = MOSWriteTracker()
        tracker.begin(terminal: .charge, charge: false, discharge: true, at: start)

        let first = tracker.expire(now: start.addingTimeInterval(30))
        let second = tracker.expire(now: start.addingTimeInterval(60))

        #expect(first)
        #expect(!second)
    }

    @Test("A command confirmed before the deadline cannot expire afterwards")
    func confirmedCommandDoesNotExpire() {
        var tracker = MOSWriteTracker()
        tracker.begin(terminal: .charge, charge: false, discharge: true, at: start)
        tracker.reconcile(chargeEnabled: false, dischargeEnabled: true)
        let expired = tracker.expire(now: start.addingTimeInterval(60))

        #expect(!expired)
    }

    @Test("Cancelling frees the buttons without reporting a timeout")
    func cancelFreesTheButtons() {
        var tracker = MOSWriteTracker()
        tracker.begin(terminal: .charge, charge: false, discharge: true, at: start)
        tracker.cancel()

        let expired = tracker.expire(now: start.addingTimeInterval(60))
        let accepted = tracker.begin(terminal: .discharge, charge: true, discharge: false, at: start)

        #expect(!expired)
        // A new command is accepted straight away.
        #expect(accepted)
    }
}
