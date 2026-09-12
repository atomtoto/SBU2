//
//  ChargeBox.swift
//  SBU2
//
//  Reproduces SBU's ChargeBox.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Charge-limit controls.
///
/// As in SBU, these settings are stored but nothing acts on them: no code outside
/// this screen and the device settings ever reads `chargeLimitSOC`.
struct ChargeBox: View {
    @Binding var settings: DeviceSettings

    /// The slider snaps to 80 %, the mark most lithium packs are happiest stopping at.
    private let magneticPoint: Double = 80
    private let magneticRange: Double = 3

    @State private var lastVibrationTriggered = false

    private var cellEmptyVoltageLight: Double { Double(settings.cellEmptyVoltage) / 1000 }
    private var cellFullVoltageLight: Double { Double(settings.cellFullVoltage) / 1000 }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Charge Limit:")
                Spacer(minLength: 25)
                Picker("Limit", selection: $settings.chargeLimitMode) {
                    Text("SOC (%)").tag(ChargeLimitMode.stateOfCharge)
                    Text("Voltage").tag(ChargeLimitMode.cellVoltage)
                }
            }
            HStack {
                if settings.chargeLimitMode == .stateOfCharge {
                    Text("\(Int(settings.chargeLimitSOC.rounded()))%")
                        .frame(width: 48)
                    Slider(value: socBinding, in: 0...100, step: 1.0)
                } else {
                    Text(String(format: "%.2f V", settings.chargeLimitVoltage))
                        .frame(width: 54)
                    Slider(value: $settings.chargeLimitVoltage,
                           in: voltageRange,
                           step: 0.01)
                }
            }
            .padding(.horizontal)

            Divider()

            HStack {
                Image(systemName: "arrow.up.circle.badge.clock")
                Toggle("Refill the battery later", isOn: refillLaterBinding)
            }
            .padding(.top, 8)

            if settings.refillLaterEnabled {
                // Only the choice of where to refill to goes away at the maximum,
                // and only because there is nothing left to choose between: "up to
                // the limit" and "up to full" are then the same instruction. The
                // refill itself still makes sense — topping the pack back up to
                // full before a given time is exactly what it is for.
                if !isAtMaximum {
                    HStack {
                        Text("Up to")
                        Spacer(minLength: 12)
                        // The limit segment carries the figure itself, so the choice
                        // reads as "back to 80 %" or "all the way" rather than as two
                        // abstractions.
                        Picker("Up to", selection: $settings.refillTarget) {
                            Text(chargeLimitText).tag(RefillTarget.chargeLimit)
                            Text("Full").tag(RefillTarget.full)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(.horizontal)
                    .padding(.top, 3)
                }

                HStack {
                    DatePicker("Select a time",
                               selection: $settings.refillDate,
                               in: Date()...,
                               displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                }
                .padding(.horizontal)
                .padding(.top, 3)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    /// The limit as it is written above, in whichever unit it was set in.
    private var chargeLimitText: String {
        settings.chargeLimitMode == .stateOfCharge
            ? "\(Int(settings.chargeLimitSOC.rounded()))%"
            : String(format: "%.2f V", settings.chargeLimitVoltage)
    }

    private var voltageRange: ClosedRange<Double> {
        cellEmptyVoltageLight < cellFullVoltageLight
            ? cellEmptyVoltageLight...cellFullVoltageLight
            : 3.0...3.65
    }

    private var isAtMaximum: Bool {
        settings.chargeLimitMode == .stateOfCharge
            ? settings.chargeLimitSOC >= 100
            : settings.chargeLimitVoltage >= cellFullVoltageLight - 0.005
    }

    /// A switch rather than a checkbox, so the row reads as something that is armed
    /// and stays armed.
    private var refillLaterBinding: Binding<Bool> {
        Binding {
            settings.refillLaterEnabled
        } set: { newValue in
            settings.refillLaterEnabled = newValue
            impact()
        }
    }

    /// Pulls the slider onto the detent and taps once when it lands there.
    private var socBinding: Binding<Double> {
        Binding {
            settings.chargeLimitSOC
        } set: { newValue in
            if abs(newValue - magneticPoint) < magneticRange {
                settings.chargeLimitSOC = magneticPoint
                if !lastVibrationTriggered {
                    lastVibrationTriggered = true
                    impact()
                }
            } else {
                settings.chargeLimitSOC = newValue
                lastVibrationTriggered = false
            }
        }
    }

    private func impact() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}
