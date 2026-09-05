//
//  TripRecorder.swift
//  SBU2
//

import CoreLocation
import Foundation
import Observation

/// Tracks speed, distance and energy use while riding, and estimates the remaining
/// range from what the pack is actually delivering.
///
/// Location updates only run while the trip screen is on screen; `start()` and `stop()`
/// are driven by that view's lifecycle so the app never holds GPS in the background.
@Observable
final class TripRecorder: NSObject {

    private(set) var currentSpeed = Measurement<UnitSpeed>(value: 0, unit: .metersPerSecond)
    private(set) var topSpeed = Measurement<UnitSpeed>(value: 0, unit: .metersPerSecond)
    private(set) var distance = Measurement<UnitLength>(value: 0, unit: .meters)
    private(set) var power = Measurement<UnitPower>(value: 0, unit: .watts)
    /// Energy per unit distance, in watt-hours per kilometre or per mile.
    private(set) var efficiency: Double = 0
    private(set) var estimatedRange = Measurement<UnitLength>(value: 0, unit: .meters)
    private(set) var authorizationDenied = false
    private(set) var isRunning = false

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var lastLocation: CLLocation?
    /// The latest pack reading, pushed in by the view so the recorder can convert
    /// speed into consumption without owning the Bluetooth connection.
    @ObservationIgnored private var reading = BasicInfo()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        isRunning = false
        manager.stopUpdatingLocation()
        lastLocation = nil
        currentSpeed.value = 0
    }

    func update(reading: BasicInfo) {
        self.reading = reading
    }

    /// Clears the trip counters without interrupting tracking.
    func reset() {
        topSpeed.value = 0
        distance.value = 0
        lastLocation = nil
    }

    var speedUnit: UnitSpeed { Locale.current.preferredSpeedUnit }
    var distanceUnit: UnitLength { Locale.current.preferredDistanceUnit }

    var efficiencyUnit: String {
        Locale.current.measurementSystem == .metric ? "Wh/km" : "Wh/mi"
    }

    /// How far into the top speed seen so far the pack is running, for the speed dial.
    var speedFraction: Double {
        let top = topSpeed.converted(to: .metersPerSecond).value
        guard top > 0 else { return 0 }
        return min(currentSpeed.converted(to: .metersPerSecond).value / top, 1)
    }
}

extension TripRecorder: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            authorizationDenied = true
        default:
            authorizationDenied = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // A negative speed means Core Location has no valid reading yet.
        guard location.speed >= 0 else {
            currentSpeed.value = 0
            efficiency = 0
            lastLocation = nil
            return
        }

        if let previous = lastLocation {
            distance.value += location.distance(from: previous)
        }
        lastLocation = location

        currentSpeed = Measurement(value: location.speed, unit: .metersPerSecond)
        if currentSpeed > topSpeed { topSpeed = currentSpeed }

        // Only discharge counts as consumption.
        let watts = max(0, -reading.current) * reading.packVoltage
        power = Measurement(value: watts, unit: .watts)

        let speedInDisplayUnit = currentSpeed.converted(to: Locale.current.preferredSpeedUnit).value
        guard speedInDisplayUnit > 1, watts > 0 else {
            efficiency = 0
            return
        }
        efficiency = watts / speedInDisplayUnit

        let remainingEnergy = reading.residualCapacity * reading.packVoltage   // Wh
        estimatedRange = Measurement(value: remainingEnergy / efficiency,
                                     unit: Locale.current.preferredDistanceUnit)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A transient fix failure is not worth surfacing; the next update will correct it.
    }
}
