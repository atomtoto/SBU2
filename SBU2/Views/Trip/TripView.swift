//
//  TripView.swift
//  SBU2
//

import SwiftUI

/// Speed, consumption and range while riding — the GPS tab of SBU.
struct TripView: View {
    @Environment(BMSConnection.self) private var connection
    @State private var recorder = TripRecorder()
    @State private var showingDialSettings = false

    var body: some View {
        @Bindable var connection = connection

        ScrollView {
            VStack(spacing: 12) {
                if recorder.authorizationDenied {
                    Card {
                        Label("SBU2 n'a pas accès à votre position. Activez-le dans Réglages pour mesurer vitesse, distance et autonomie.",
                              systemImage: "location.slash")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                DialsCard(settings: connection.settings,
                          info: connection.info,
                          recorder: recorder) {
                    showingDialSettings = true
                }

                TripFiguresCard(settings: connection.settings,
                                info: connection.info,
                                recorder: recorder)

                Button(role: .destructive) {
                    recorder.reset()
                } label: {
                    Label("Réinitialiser le trajet", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .onAppear {
            recorder.update(reading: connection.info)
            recorder.start()
        }
        .onDisappear { recorder.stop() }
        .onChange(of: connection.info) { _, reading in
            recorder.update(reading: reading)
        }
        .sheet(isPresented: $showingDialSettings) {
            NavigationStack {
                DialsSettingsView(settings: $connection.settings)
            }
            .presentationDetents([.medium])
        }
    }
}

// MARK: - Dials

private struct DialsCard: View {
    let settings: DeviceSettings
    let info: BasicInfo
    let recorder: TripRecorder
    let onEdit: () -> Void

    private var anyDialShown: Bool {
        settings.showPowerDial || settings.showSpeedDial || settings.showRangeDial
    }

    var body: some View {
        Card {
            if anyDialShown {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { dials }
                    VStack(spacing: 16) { dials }
                }
            } else {
                Button(action: onEdit) {
                    Label("Ajouter des cadrans", systemImage: "gauge.with.dots.needle.bottom.50percent")
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
        .contextMenu {
            Button("Modifier les cadrans", systemImage: "slider.horizontal.3", action: onEdit)
        }
    }

    @ViewBuilder
    private var dials: some View {
        if settings.showPowerDial {
            Dial(fraction: abs(info.power) / max(Double(settings.expectedPower), 1),
                 tint: info.current >= 0 ? .purple : .blue,
                 value: info.powerText,
                 caption: "Puissance")
        }
        if settings.showSpeedDial {
            Dial(fraction: recorder.speedFraction,
                 tint: .green,
                 value: speedText,
                 caption: "Vitesse")
        }
        if settings.showRangeDial {
            Dial(fraction: rangeFraction,
                 tint: rangeTint,
                 value: rangeText,
                 caption: "Autonomie")
        }
    }

    private var speedText: String {
        let speed = recorder.currentSpeed.converted(to: recorder.speedUnit)
        return speed.value.formatted(decimals: 0, unit: recorder.speedUnit.symbol)
    }

    private var rangeText: String {
        let range = recorder.estimatedRange.converted(to: recorder.distanceUnit)
        return range.value.formatted(decimals: 0, unit: recorder.distanceUnit.symbol)
    }

    /// How the projected total trip compares with the range the user expects.
    private var rangeRatio: Double {
        let projected = recorder.estimatedRange.converted(to: recorder.distanceUnit).value
            + recorder.distance.converted(to: recorder.distanceUnit).value
        return projected / max(Double(settings.expectedRange), 1)
    }

    private var rangeFraction: Double { min(rangeRatio, 1) }

    private var rangeTint: Color {
        switch rangeRatio {
        case ..<0.5: .red
        case ..<1: .orange
        default: .green
        }
    }
}

private struct Dial: View {
    let fraction: Double
    let tint: Color
    let value: String
    let caption: String

    var body: some View {
        RingGauge(fraction: fraction, tint: tint) {
            VStack(spacing: 2) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(caption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(minWidth: 104, maxWidth: 150)
        .frame(height: 116)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(caption) : \(value)")
    }
}

// MARK: - Figures

private struct TripFiguresCard: View {
    let settings: DeviceSettings
    let info: BasicInfo
    let recorder: TripRecorder

    var body: some View {
        Card {
            VStack(spacing: 10) {
                row("Vitesse max", recorder.topSpeed.converted(to: recorder.speedUnit)
                    .value.formatted(decimals: 0, unit: recorder.speedUnit.symbol))

                if !settings.showSpeedDial {
                    Divider()
                    row("Vitesse", recorder.currentSpeed.converted(to: recorder.speedUnit)
                        .value.formatted(decimals: 0, unit: recorder.speedUnit.symbol))
                }
                if !settings.showPowerDial {
                    Divider()
                    row("Puissance", recorder.power.value.formatted(decimals: 0, unit: "W"))
                }

                Divider()
                row("Consommation", recorder.efficiency > 0
                    ? recorder.efficiency.formatted(decimals: 0, unit: recorder.efficiencyUnit)
                    : "—")

                Divider()
                HStack {
                    Text("Batterie").foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    RingGauge(fraction: Double(info.stateOfCharge) / 100,
                              tint: .forStateOfCharge(info.stateOfCharge),
                              lineWidth: 4) { EmptyView() }
                        .frame(width: 16, height: 16)
                    Text(info.stateOfChargeText).monospacedDigit()
                }
                .font(.subheadline)

                if !settings.showRangeDial {
                    Divider()
                    row("Autonomie estimée", recorder.estimatedRange.converted(to: recorder.distanceUnit)
                        .value.formatted(decimals: 1, unit: recorder.distanceUnit.symbol))
                }

                Divider()
                row("Distance parcourue", recorder.distance.converted(to: recorder.distanceUnit)
                    .value.formatted(decimals: 2, unit: recorder.distanceUnit.symbol))
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }
}
