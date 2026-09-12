//
//  GPSView.swift
//  SBU2
//
//  Reproduces SBU's GPSView: the dials, the figures list and the reset button.
//

import SwiftUI

struct GPSView: View {
    @Environment(BMSConnection.self) private var connection
    @State private var recorder = TripRecorder()
    @State private var showingDialSettings = false
    @State private var orientation = InterfaceOrientationObserver()

    /// The rotate hint only earns its place once all three dials are competing for
    /// the same row — with one or two, portrait already has the room.
    private var allDialsShown: Bool {
        connection.settings.showPowerDial
            && connection.settings.showSpeedDial
            && connection.settings.showRangeDial
    }

    var body: some View {
        @Bindable var connection = connection

        VStack(spacing: 10) {
            ScrollView {
                // One stack at the same 10pt the overview stacks its boxes at,
                // rather than a top padding per box: the gap between the dials and
                // the figures now matches every other screen's.
                VStack(spacing: 10) {
                    DialsView(settings: connection.settings,
                              info: connection.info,
                              recorder: recorder) {
                        showingDialSettings = true
                    }

                    if allDialsShown && orientation.isPortrait {
                        HintBanner(symbol: "iphone.landscape",
                                   message: "Rotate your phone: three dials fit better in landscape.")
                    }

                    GPSListView(settings: connection.settings,
                                info: connection.info,
                                recorder: recorder)

                    if recorder.authorizationDenied {
                        HintBanner(symbol: "location.slash",
                                   message: "Location access is off. Enable it in Settings to measure speed, distance and range.")
                    }
                }
                .padding(.top, 15)
                .padding(.bottom, 20)
            }

            HStack(alignment: .center) {
                // The same pill the MOSFET buttons use — only the colour and
                // symbol say this one is Reset.
                GlassPillButton(title: "Reset", color: .red, symbol: "minus.circle") {
                    recorder.reset()
                }
                .padding(.bottom, 20)
            }
        }
        .padding(.horizontal, 3)
        .onAppear {
            OrientationLock.shared.allowAllOrientations()
            orientation.start()
            recorder.update(reading: connection.info)
            recorder.start()
        }
        .onDisappear {
            OrientationLock.shared.lockToPortrait()
            orientation.stop()
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

/// A one-line notice, icon plus footnote, on the same frosted pill used for both
/// the location-access warning and the rotate-to-landscape hint below.
private struct HintBanner: View {
    let symbol: String
    let message: String

    var body: some View {
        HStack {
            Image(systemName: symbol)
                .foregroundColor(.accent) //
            Text(message)
                .font(.footnote)
                .foregroundColor(.accent)
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        // The same gutter the two boxes take, since a hint sits between them.
        .padding(.horizontal, 15)
    }
}

// MARK: - Dials

private struct DialsView: View {
    let settings: DeviceSettings
    let info: BasicInfo
    let recorder: TripRecorder
    let onEdit: () -> Void

    private var enabledDialCount: Int {
        [settings.showPowerDial, settings.showSpeedDial, settings.showRangeDial].filter { $0 }.count
    }

    private var anyDial: Bool { enabledDialCount > 0 }

    /// A single dial has the whole row to itself, so it can afford to be a lot
    /// easier to read at a glance than the size two or three of them have to share.
    private var isSingleDial: Bool { enabledDialCount == 1 }

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
                             caption: "Power",
                             large: isSingleDial)
                        Spacer()
                    }
                    if settings.showSpeedDial {
                        Dial(fraction: recorder.speedFraction,
                             tint: .green,
                             value: recorder.currentSpeedText,
                             caption: "Speed",
                             large: isSingleDial)
                        Spacer()
                    }
                    if settings.showRangeDial {
                        Dial(fraction: rangeRatio / 2,
                             tint: rangeTint,
                             value: recorder.estimatedRangeText,
                             caption: "Remaining",
                             captionScale: 15.0 / 17.0,
                             large: isSingleDial)
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
        .padding(.horizontal, 15)
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
    /// Multiplies the caption's font size — "Remaining" needs to run smaller than
    /// "Power" or "Speed" to fit under the same width.
    var captionScale: CGFloat = 1
    /// The one dial showing, with the row to itself.
    var large: Bool = false

    private var minDiameter: CGFloat { large ? 175 : 115 }
    private var maxDiameter: CGFloat { large ? 210 : 140 }
    private var height: CGFloat { large ? 186 : 124 }
    private var lineWidth: CGFloat { large ? 18 : 12 }
    private var valueFontSize: CGFloat { large ? 36 : 23 }
    private var captionFontSize: CGFloat { (large ? 26 : 17) * captionScale }
    private var labelInset: CGFloat { large ? 26 : 18 }
    private var outerPadding: CGFloat { large ? 12 : 8 }

    var body: some View {
        RingGauge(fraction: fraction, tint: tint, lineWidth: lineWidth) {
            VStack {
                Text(value)
                    .font(.system(size: valueFontSize, weight: .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(caption)
                    .font(.system(size: captionFontSize, weight: .bold))
                    .multilineTextAlignment(.center)
                    .opacity(0.65)
            }
            .padding(.horizontal, labelInset)
        }
        .frame(minWidth: minDiameter, maxWidth: maxDiameter)
        .frame(height: height)
        .padding(outerPadding)
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
            // The same card every other summary uses, with real list-row metrics
            // (LabeledContent's secondary-coloured value, a 44pt row) instead of
            // the cramped, tightly-padded rows this used to be built from.
            Card {
                VStack(spacing: 0) {
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
                    LabeledContent("Battery remaining") {
                        HStack(spacing: 6) {
                            RingGauge(fraction: Double(info.stateOfCharge) / 100,
                                      tint: .stateOfChargeTrip(info.stateOfCharge),
                                      lineWidth: 4) { EmptyView() }
                                .frame(width: 13, height: 13)
                            Text(info.stateOfChargeText)
                        }
                    }
                    .frame(minHeight: 44)
                    Divider()
                    if let hottest = info.temperatures.max() {
                        LabeledContent("Max temperature") {
                            HStack(spacing: 6) {
                                IndicatorLight(tint: .packTemperature(hottest))
                                Text(info.temperatureText(hottest))
                                    .monospacedDigit()
                            }
                        }
                        .frame(minHeight: 44)
                        Divider()
                    }
                    if !settings.showRangeDial {
                        row("Remaining range", recorder.estimatedRangeText)
                        Divider()
                    }
                    row("Total distance", recorder.distanceText)
                }
            }

            // Footer de type "List Section Footer"
                    Text("Values represent the average of the last 5 measurements")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading) // Aligné à gauche comme un vrai footer
                        .padding(.horizontal, 16) // Aligne visuellement le 'V' avec le 'T' de "Top speed" au-dessus
        }
        .padding(.horizontal, 15)
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
            .frame(minHeight: 44)
    }
}

/// A small coloured light, haloed so it reads as an indicator rather than as a
/// bullet point in front of the figure.
private struct IndicatorLight: View {
    let tint: Color

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 9, height: 9)
            .overlay {
                Circle().stroke(tint.opacity(0.3), lineWidth: 3.5)
            }
            .frame(width: 16, height: 16)
            .animation(.easeInOut(duration: 0.4), value: tint)
    }
}
