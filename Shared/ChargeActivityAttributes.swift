//
//  ChargeActivityAttributes.swift
//  SBU2
//

import ActivityKit
import Foundation

/// The immutable device identity and the values that change while a pack charges.
///
/// This file is compiled into both the app and its widget extension. Keeping the
/// payload small matters: ActivityKit persists and transfers it every time the Live
/// Activity is refreshed.
struct ChargeActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        let stateOfCharge: Int
        let chargingPowerWatts: Int
        let estimatedCompletionDate: Date?
    }

    let deviceName: String
}
