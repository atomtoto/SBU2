//
//  MOSWriteTrackerTests.swift
//  SBU2Tests
//

import Foundation
import Testing
@testable import SBU2

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
        #expect(tracker.begin(terminal: .charge, charge: false, discharge: true, at: start))
        #expect(!tracker.begin(terminal: .discharge, charge: false, discharge: false, at: start))

        // The first request is untouched, so the wrong write cannot be sent.
        #expect(tracker.isWaiting(for: .charge))
        #expect(tracker.request?.discharge == true)
    }

    @Test("The wait ends when the pack reports the requested state")
    func reconcilesOnMatchingState() {
        var tracker = MOSWriteTracker()
        tracker.begin(terminal: .charge, charge: false, discharge: true, at: start)

        #expect(tracker.reconcile(chargeEnabled: false, dischargeEnabled: true))
        #expect(!tracker.isBusy)
    }

    @Test("A frame that still shows the old state keeps the spinner running")
    func staleFrameDoesNotResolve() {
        var tracker = MOSWriteTracker()
        tracker.begin(terminal: .charge, charge: false, discharge: true, at: start)

        #expect(!tracker.reconcile(chargeEnabled: true, dischargeEnabled: true))
        #expect(tracker.isWaiting(for: .charge))
    }

    @Test("A frame where the other terminal also moved does not resolve")
    func partialMatchDoesNotResolve() {
        var tracker = MOSWriteTracker()
        tracker.begin(terminal: .charge, charge: false, discharge: true, at: start)

        #expect(!tracker.reconcile(chargeEnabled: false, dischargeEnabled: false))
        #expect(tracker.isBusy)
    }

    @Test("Reconciling with no command in flight reports nothing")
    func reconcileWhenIdle() {
        var tracker = MOSWriteTracker()
        #expect(!tracker.reconcile(chargeEnabled: true, dischargeEnabled: true))
    }

    @Test("The command expires once the deadline passes")
    func expiresAfterTimeout() {
        var tracker = MOSWriteTracker()
        tracker.begin(terminal: .discharge, charge: true, discharge: false, at: start)

        #expect(!tracker.expire(now: start.addingTimeInterval(9.9)))
        #expect(tracker.isBusy)

        #expect(tracker.expire(now: start.addingTimeInterval(10)))
        #expect(!tracker.isBusy)
    }

    @Test("Expiry is reported once, so the error is surfaced a single time")
    func expiresOnlyOnce() {
        var tracker = MOSWriteTracker()
        tracker.begin(terminal: .charge, charge: false, discharge: true, at: start)

        #expect(tracker.expire(now: start.addingTimeInterval(30)))
        #expect(!tracker.expire(now: start.addingTimeInterval(60)))
    }

    @Test("A command confirmed before the deadline cannot expire afterwards")
    func confirmedCommandDoesNotExpire() {
        var tracker = MOSWriteTracker()
        tracker.begin(terminal: .charge, charge: false, discharge: true, at: start)
        tracker.reconcile(chargeEnabled: false, dischargeEnabled: true)

        #expect(!tracker.expire(now: start.addingTimeInterval(60)))
    }

    @Test("Cancelling frees the buttons without reporting a timeout")
    func cancelFreesTheButtons() {
        var tracker = MOSWriteTracker()
        tracker.begin(terminal: .charge, charge: false, discharge: true, at: start)
        tracker.cancel()

        #expect(!tracker.isBusy)
        #expect(!tracker.expire(now: start.addingTimeInterval(60)))
        // A new command is accepted straight away.
        #expect(tracker.begin(terminal: .discharge, charge: true, discharge: false, at: start))
    }
}
