//
//  ChargeLimitCard.swift
//  SBU2
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Charge-limit controls, ported from SBU.
///
/// These settings are stored but nothing acts on them yet: SBU never enforced the
/// limit either — no code outside its own settings and overview screens ever read
/// `chargeLimitSOC`. The footer says so rather than implying the app will cut the
/// charge on its own.
struct ChargeLimitCard: View {
    @Binding var settings: DeviceSettings

    /// The 80 % mark most lithium packs are happiest stopping at; the slider snaps to it.
    private let detent: Double = 80
    private let detentRange: Double = 2

    @State private var snapped = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CardHeader(title: "Limite de charge", systemImage: "bolt.badge.clock")
                    Picker("Type de limite", selection: $settings.chargeLimitMode) {
                        ForEach(ChargeLimitMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }

                if settings.chargeLimitMode == .stateOfCharge {
                    HStack(spacing: 12) {
                        Text("\(Int(settings.chargeLimitSOC.rounded())) %")
                            .monospacedDigit()
                            .frame(width: 54, alignment: .leading)
                        Slider(value: socBinding, in: 0...100, step: 1)
                    }
                } else {
                    HStack(spacing: 12) {
                        Text(settings.chargeLimitVoltage.formatted(decimals: 2, unit: "V"))
                            .monospacedDigit()
                            .frame(width: 62, alignment: .leading)
                        Slider(value: $settings.chargeLimitVoltage,
                               in: voltageRange,
                               step: 0.01)
                    }
                }

                Divider()

                Toggle(isOn: $settings.refillLaterEnabled) {
                    Label("Recharger plus tard", systemImage: "arrow.up.circle.badge.clock")
                }
                .disabled(isAtMaximum)
                .opacity(isAtMaximum ? 0.5 : 1)

                if settings.refillLaterEnabled && !isAtMaximum {
                    DatePicker("Reprendre la charge",
                               selection: $settings.refillDate,
                               in: Date()...,
                               displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                }

                Text("Ces réglages sont enregistrés mais l'application ne coupe pas encore la charge automatiquement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: isAtMaximum) { _, atMaximum in
            if atMaximum { settings.refillLaterEnabled = false }
        }
    }

    private var voltageRange: ClosedRange<Double> {
        let low = Double(settings.cellEmptyVoltage) / 1000
        let high = Double(settings.cellFullVoltage) / 1000
        return low < high ? low...high : 3.0...3.65
    }

    private var isAtMaximum: Bool {
        settings.chargeLimitMode == .stateOfCharge
            ? settings.chargeLimitSOC >= 100
            : settings.chargeLimitVoltage >= voltageRange.upperBound
    }

    /// Pulls the slider onto the 80 % detent and taps once when it lands there.
    private var socBinding: Binding<Double> {
        Binding {
            settings.chargeLimitSOC
        } set: { newValue in
            if abs(newValue - detent) < detentRange {
                settings.chargeLimitSOC = detent
                if !snapped {
                    snapped = true
                    playSelectionFeedback()
                }
            } else {
                settings.chargeLimitSOC = newValue
                snapped = false
            }
        }
    }

    private func playSelectionFeedback() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}
