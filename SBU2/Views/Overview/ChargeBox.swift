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
                Text("Refill the battery later")
                Spacer()
                Button {
                    settings.refillLaterEnabled.toggle()
                    impact()
                } label: {
                    Image(systemName: settings.refillLaterEnabled ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(settings.refillLaterEnabled ? .accentColor : .gray)
                        .font(.system(size: 20))
                }
            }
            .padding(.top, 8)
            .disabled(isAtMaximum)
            .opacity(isAtMaximum ? 0.5 : 1.0)

            if settings.refillLaterEnabled {
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
        .onChange(of: isAtMaximum) { _, atMaximum in
            if atMaximum { settings.refillLaterEnabled = false }
        }
        .background {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    private var voltageRange: ClosedRange<Double> {
        cellEmptyVoltageLight < cellFullVoltageLight
            ? cellEmptyVoltageLight...cellFullVoltageLight
            : 3.0...3.65
    }

    private var isAtMaximum: Bool {
        settings.chargeLimitMode == .stateOfCharge
            ? settings.chargeLimitSOC == 100
            : settings.chargeLimitVoltage == cellFullVoltageLight
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
