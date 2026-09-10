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
                    .tint(.accent)
            }
            .padding(.top, 8)
            .disabled(isAtMaximum)
            .opacity(isAtMaximum ? 0.5 : 1.0)

            if settings.refillLaterEnabled {
                HStack {
                    Text("Up to")
                    Spacer(minLength: 12)
                    // The limit segment carries the figure itself, so the choice
                    // reads as "back to 80 %" or "all the way" rather than as two
                    // abstractions.
                    RefillTargetSelector(target: $settings.refillTarget,
                                         limitTitle: chargeLimitText)
                        .frame(maxWidth: 220)
                }
                .padding(.horizontal)
                .padding(.top, 3)

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
            ? settings.chargeLimitSOC == 100
            : settings.chargeLimitVoltage == cellFullVoltageLight
    }

    /// A switch rather than a checkbox, so the row reads as something that is armed
    /// and stays armed. Orange keeps it apart from the accent colour the sliders and
    /// the cell bars already use.
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

/// Two options laid out like a segmented control, drawn here rather than by the
/// system.
///
/// A `Picker` in the segmented style hands its titles to UIKit, which paints them
/// with its own attributes and ignores `foregroundStyle` — so "Full" could never go
/// green inside one. Everything else about it is meant to read as the system
/// control does.
private struct RefillTargetSelector: View {
    @Binding var target: RefillTarget
    /// The charge limit as it is written above, so the option names the figure.
    let limitTitle: String

    var body: some View {
        HStack(spacing: 2) {
            segment(.chargeLimit, title: limitTitle, selectedTint: .primary)
            // Green because this is the option that takes the pack all the way up,
            // which is the one worth noticing at a glance.
            segment(.full, title: "Full", selectedTint: .green)
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.quaternary)
        }
    }

    private func segment(_ value: RefillTarget, title: String, selectedTint: Color) -> some View {
        let isSelected = target == value
        return Button {
            target = value
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
        } label: {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isSelected ? selectedTint : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.background)
                        .opacity(isSelected ? 1 : 0)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
