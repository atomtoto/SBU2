//
//  GPSView.swift
//  SBU2
//
//  Reproduces SBU's GPSView: the dials, the figures list and the reset button.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct GPSView: View {
    @Environment(BMSConnection.self) private var connection
    @State private var recorder = TripRecorder()
    @State private var showingDialSettings = false

    var body: some View {
        @Bindable var connection = connection

        VStack(spacing: 10) {
            ScrollView {
                DialsView(settings: connection.settings,
                          info: connection.info,
                          recorder: recorder) {
                    showingDialSettings = true
                }
                .padding(.top, 15)

                GPSListView(settings: connection.settings,
                            info: connection.info,
                            recorder: recorder)
                    .padding(.top, 15)
                    .padding(.bottom, 20)

                if recorder.authorizationDenied {
                    HStack {
                        Image(systemName: "location.slash")
                        Text("Location access is off. Enable it in Settings to measure speed, distance and range.")
                            .font(.footnote)
                    }
                    .padding(.horizontal)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
            }

            HStack(alignment: .center) {
                Button {
                    recorder.reset()
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .foregroundColor(Color(uiColor: .secondarySystemBackground))
                            .frame(width: 140, height: 37)
                        HStack {
                            Text("Reset")
                                .font(.system(size: 16))
                            Image(systemName: "minus.circle")
                        }
                        .foregroundColor(Color.red)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .padding(.horizontal, 3)
        .onAppear {
            OrientationLock.shared.allowAllOrientations()
            recorder.update(reading: connection.info)
            recorder.start()
        }
        .onDisappear {
            OrientationLock.shared.lockToPortrait()
            recorder.stop()
        }
        .onChange(of: connection.info) { _, reading in
            recorder.update(reading: reading)
        }
        .sheet(isPresented: $showingDialSettings) {
            NavigationStack {
                DialsSettingsView(settings: $connection.settings)
            }
            .presentationDetents([.fraction(0.4)])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Dials

private struct DialsView: View {
    let settings: DeviceSettings
    let info: BasicInfo
    let recorder: TripRecorder
    let onEdit: () -> Void

    private var anyDial: Bool {
        settings.showPowerDial || settings.showSpeedDial || settings.showRangeDial
    }

    /// SBU drew the range arc at half scale, so a ratio of 1 fills only half the
    /// ring. Kept as it was, otherwise the dial would read differently from before.
    private var rangeRatio: Double {
        let projected = recorder.estimatedRange.converted(to: recorder.distanceUnit).value
            + recorder.distance.converted(to: recorder.distanceUnit).value
        return projected / max(Double(settings.expectedRange), 1)
    }

    var body: some View {
        VStack {
            if anyDial {
                HStack {
                    Spacer()
                    if settings.showPowerDial {
                        Dial(fraction: abs(info.power) / max(Double(settings.expectedPower), 1),
                             tint: info.current >= 0 ? .purple : .blue,
                             value: info.powerText,
                             caption: "Power")
                        Spacer()
                    }
                    if settings.showSpeedDial {
                        Dial(fraction: recorder.speedFraction,
                             tint: .green,
                             value: recorder.currentSpeedText,
                             caption: "Speed")
                        Spacer()
                    }
                    if settings.showRangeDial {
                        Dial(fraction: rangeRatio / 2,
                             tint: rangeTint,
                             value: recorder.estimatedRangeText,
                             caption: "Remaining",
                             captionSize: 15)
                        Spacer()
                    }
                }
                .frame(alignment: .center)
            } else {
                HStack {
                    Spacer()
                    Image(systemName: "gauge.badge.plus")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 17))
                    Text("(long press here to add dials)")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 17))
                    Spacer()
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .padding(.horizontal, 22)
        .contextMenu {
            Button(action: onEdit) {
                Text("Edit dials")
                Image(systemName: "pencil")
            }
        }
    }

    private var rangeTint: Color {
        switch rangeRatio {
        case ..<0.5: .red
        case ..<1: .yellow
        case ..<1.5: .green
        default: Color(red: 0 / 255, green: 230 / 255, blue: 248 / 255)
        }
    }
}

private struct Dial: View {
    let fraction: Double
    let tint: Color
    let value: String
    let caption: String
    var captionSize: CGFloat = 17

    var body: some View {
        RingGauge(fraction: fraction, tint: tint) {
            VStack {
                Text(value)
                    .font(.system(size: 23, weight: .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(caption)
                    .font(.system(size: captionSize, weight: .bold))
                    .multilineTextAlignment(.center)
                    .opacity(0.65)
            }
            .padding(.horizontal, 18)
        }
        .frame(minWidth: 115, maxWidth: 140)
        .frame(height: 124)
        .padding(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(caption): \(value)")
    }
}

// MARK: - Figures

private struct GPSListView: View {
    let settings: DeviceSettings
    let info: BasicInfo
    let recorder: TripRecorder

    var body: some View {
        VStack {
            VStack {
                row("Top speed", recorder.topSpeedText)
                Divider()
                if !settings.showSpeedDial {
                    row("Current speed", recorder.currentSpeedText)
                    Divider()
                }
                if !settings.showPowerDial {
                    row("Power (avg.)", recorder.powerText)
                    Divider()
                }
                row("Efficiency", recorder.efficiencyText)
                Divider()
                HStack {
                    Text("Battery remaining")
                    Spacer()
                    RingGauge(fraction: Double(info.stateOfCharge) / 100,
                              tint: .stateOfChargeTrip(info.stateOfCharge),
                              lineWidth: 4) { EmptyView() }
                        .frame(width: 13, height: 13)
                    Text(info.stateOfChargeText)
                }
                .padding(5)
                Divider()
                if !settings.showRangeDial {
                    row("Remaining range", recorder.estimatedRangeText)
                    Divider()
                }
                row("Total distance", recorder.distanceText)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.ultraThinMaterial)
            }

            HStack {
                Text("Values represent the average of the last 5 measurements")
                    .font(.footnote)
                    .foregroundColor(Color.gray)
            }
            .padding(.horizontal)
        }
        .padding(.horizontal, 22)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
        }
        .padding(5)
    }
}
