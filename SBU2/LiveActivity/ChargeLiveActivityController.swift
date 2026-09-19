//
//  ChargeLiveActivityController.swift
//  SBU2
//

import ActivityKit
import Foundation

/// Owns the single charging Live Activity published by the app.
///
/// BMS readings arrive every second, while a Live Activity is meant for glanceable
/// changes rather than telemetry. Values are therefore rounded and only meaningful
/// changes are sent to ActivityKit. The completion date lets the system render a
/// live countdown even when iOS suspends the app and Bluetooth polling pauses.
actor ChargeLiveActivityController {
    private static let chargingThreshold = 0.05
    private static let minimumUpdateInterval: TimeInterval = 30
    private static let completionShiftWorthPublishing: TimeInterval = 120

    private var activity: Activity<ChargeActivityAttributes>?
    private var lastPublishedState: ChargeActivityAttributes.ContentState?
    private var lastPublishedAt: Date?
    private var idleReadings = 0

    func synchronize(reading: BasicInfo,
                     remainingHours: Double?,
                     deviceName: String,
                     at now: Date = .now) async {
        guard reading.current > Self.chargingThreshold else {
            idleReadings += 1
            // A charger or a BMS can report zero for a sample while changing mode.
            // Three consecutive readings avoid ending and recreating the activity.
            if idleReadings >= 3 {
                await endImmediately()
            }
            return
        }

        idleReadings = 0
        let state = makeState(reading: reading, remainingHours: remainingHours, at: now)

        if activity == nil {
            activity = Activity<ChargeActivityAttributes>.activities.first
        }

        guard let activity else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            do {
                let attributes = ChargeActivityAttributes(deviceName: deviceName)
                self.activity = try Activity.request(attributes: attributes,
                                                     content: content(for: state, at: now),
                                                     pushType: nil)
                lastPublishedState = state
                lastPublishedAt = now
            } catch {
                // Live Activities can be disabled by the user or temporarily refused
                // by the system. Charging telemetry must continue either way.
            }
            return
        }

        guard shouldPublish(state, at: now) else { return }
        await activity.update(content(for: state, at: now))
        lastPublishedState = state
        lastPublishedAt = now
    }

    func endImmediately() async {
        if activity == nil {
            activity = Activity<ChargeActivityAttributes>.activities.first
        }
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
        lastPublishedState = nil
        lastPublishedAt = nil
        idleReadings = 0
    }

    private func makeState(reading: BasicInfo,
                           remainingHours: Double?,
                           at now: Date) -> ChargeActivityAttributes.ContentState {
        let completionDate = remainingHours.flatMap { hours -> Date? in
            guard hours.isFinite, hours > 0 else { return nil }
            return now.addingTimeInterval(hours * 3_600)
        }
        let power = max(0, reading.packVoltage * reading.current)
        return ChargeActivityAttributes.ContentState(
            stateOfCharge: min(max(reading.stateOfCharge, 0), 100),
            chargingPowerWatts: Int((power / 10).rounded()) * 10,
            estimatedCompletionDate: completionDate
        )
    }

    private func content(for state: ChargeActivityAttributes.ContentState,
                         at now: Date) -> ActivityContent<ChargeActivityAttributes.ContentState> {
        ActivityContent(state: state,
                        staleDate: now.addingTimeInterval(3 * 60),
                        relevanceScore: Double(state.stateOfCharge) / 100)
    }

    private func shouldPublish(_ state: ChargeActivityAttributes.ContentState,
                               at now: Date) -> Bool {
        guard let previous = lastPublishedState, let lastPublishedAt else { return true }
        if state.stateOfCharge != previous.stateOfCharge { return true }
        if abs(state.chargingPowerWatts - previous.chargingPowerWatts) >= 30 { return true }

        switch (state.estimatedCompletionDate, previous.estimatedCompletionDate) {
        case let (new?, old?):
            if abs(new.timeIntervalSince(old)) >= Self.completionShiftWorthPublishing { return true }
        case (nil, nil):
            break
        default:
            return true
        }
        return now.timeIntervalSince(lastPublishedAt) >= Self.minimumUpdateInterval
    }
}
