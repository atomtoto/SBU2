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
                DialsView(settings: connection.settings,
                          info: connection.info,
                          recorder: recorder) {
                    showingDialSettings = true
                }
                .padding(.top, 15)

                if allDialsShown && orientation.isPortrait {
                    HintBanner(symbol: "iphone.landscape",
                               message: "Rotate your phone: three dials fit better in landscape.")
                }

                GPSListView(settings: connection.settings,
                            info: connection.info,
                            recorder: recorder)
                    .padding(.top, 15)
                    .padding(.bottom, 20)

                if recorder.authorizationDenied {
                    HintBanner(symbol: "location.slash",
                               message: "Location access is off. Enable it in Settings to measure speed, distance and range.")
                }
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
            Text(message)
                .font(.footnote)
        }
        .padding(.horizontal)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Dials

/// One dial's content, before the row decides how big to draw it.
private struct DialSpec: Identifiable {
    let id: String
    let fraction: Double
    let tint: Color
    let value: String
    let caption: String
    /// Multiplies the caption's font size — "Remaining" needs to run smaller than
    /// "Power" or "Speed" to fit under the same width.
    var captionScale: CGFloat = 1
    /// The dial the row gives a bigger share of the width — Speed, the one figure
    /// worth glancing at first while moving.
    var isHero: Bool = false
}

private struct DialsView: View {
    let settings: DeviceSettings
    let info: BasicInfo
    let recorder: TripRecorder
    let onEdit: () -> Void

    /// SBU drew the range arc at half scale, so a ratio of 1 fills only half the
    /// ring. Kept as it was, otherwise the dial would read differently from before.
    private var rangeRatio: Double {
        let projected = recorder.estimatedRange.converted(to: recorder.distanceUnit).value
            + recorder.distance.converted(to: recorder.distanceUnit).value
        return projected / max(Double(settings.expectedRange), 1)
    }

    private var rangeTint: Color {
        switch rangeRatio {
        case ..<0.5: .red
        case ..<1: .yellow
        case ..<1.5: .green
        default: Color(red: 0 / 255, green: 230 / 255, blue: 248 / 255)
        }
    }

    private var specs: [DialSpec] {
        var specs: [DialSpec] = []
        if settings.showPowerDial {
            specs.append(DialSpec(id: "power",
                                   fraction: abs(info.power) / max(Double(settings.expectedPower), 1),
                                   tint: info.current >= 0 ? .purple : .blue,
                                   value: info.powerText,
                                   caption: "Power"))
        }
        if settings.showSpeedDial {
            specs.append(DialSpec(id: "speed",
                                   fraction: recorder.speedFraction,
                                   tint: .green,
                                   value: recorder.currentSpeedText,
                                   caption: "Speed",
                                   isHero: true))
        }
        if settings.showRangeDial {
            specs.append(DialSpec(id: "range",
                                   fraction: rangeRatio / 2,
                                   tint: rangeTint,
                                   value: recorder.estimatedRangeText,
                                   caption: "Remaining",
                                   captionScale: 15.0 / 17.0))
        }
        return specs
    }

    var body: some View {
        VStack {
            if specs.isEmpty {
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
            } else {
                DialsRow(specs: specs)
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
}

/// A dial, sized. Keeping this as its own `Identifiable` rather than zipping into
/// a bare tuple gives `ForEach` a straightforward `id` to key rows by.
private struct SizedDial: Identifiable {
    let spec: DialSpec
    let diameter: CGFloat
    var id: String { spec.id }
}

/// Sizes each dial from the width actually available, so three of them never add
/// up to more than that — the way three fixed 140pt dials used to, widening the
/// whole card (and everything lined up under it) past the edge of the screen. The
/// hero dial gets a bigger slice of that width; the rest split what's left evenly.
private struct DialsRow: View {
    let specs: [DialSpec]

    private static let heroWeight: CGFloat = 1.22
    private static let maxDiameter: CGFloat = 140
    private static let minDiameter: CGFloat = 60
    private static let spacing: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let sized = zip(specs, diameters(in: geometry.size.width))
                .map { SizedDial(spec: $0, diameter: $1) }
            HStack(spacing: Self.spacing) {
                Spacer(minLength: 0)
                ForEach(sized) { item in
                    Dial(spec: item.spec, diameter: item.diameter)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: Self.maxDiameter)
    }

    private func diameters(in width: CGFloat) -> [CGFloat] {
        guard !specs.isEmpty else { return [] }
        let totalSpacing = Self.spacing * CGFloat(specs.count - 1)
        let available = max(width - totalSpacing, 0)
        let weights = specs.map { $0.isHero ? Self.heroWeight : 1 }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return specs.map { _ in Self.minDiameter } }
        return weights.map { min(Self.maxDiameter, max(Self.minDiameter, available * $0 / totalWeight)) }
    }
}

private struct Dial: View {
    let spec: DialSpec
    let diameter: CGFloat

    /// The dials' inner label and stroke scale with the diameter chosen for them,
    /// so a shrunk dial (three of them side by side) still reads at a glance
    /// instead of clipping its own text. At the 140pt max these land on the exact
    /// figures the fixed-size dial used before.
    private func scaled(_ factor: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        min(upper, max(lower, diameter * factor))
    }

    private var lineWidth: CGFloat { scaled(0.086, min: 6, max: 12) }
    private var valueFontSize: CGFloat { scaled(0.164, min: 13, max: 23) }
    private var captionFontSize: CGFloat { scaled(0.121, min: 10, max: 17) * spec.captionScale }
    private var labelInset: CGFloat { scaled(0.129, min: 4, max: 18) }

    var body: some View {
        RingGauge(fraction: spec.fraction, tint: spec.tint, lineWidth: lineWidth) {
            VStack {
                Text(spec.value)
                    .font(.system(size: valueFontSize, weight: .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(spec.caption)
                    .font(.system(size: captionFontSize, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .opacity(0.65)
            }
            .padding(.horizontal, labelInset)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(spec.caption): \(spec.value)")
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
                    if !settings.showRangeDial {
                        row("Remaining range", recorder.estimatedRangeText)
                        Divider()
                    }
                    row("Total distance", recorder.distanceText)
                }
            }

            HStack {
                Text("Values represent the average of the last 5 measurements")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
        .padding(.horizontal, 22)
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
            .frame(minHeight: 44)
    }
}
