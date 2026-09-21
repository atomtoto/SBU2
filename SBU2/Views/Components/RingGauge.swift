//
//  RingGauge.swift
//  SBU2
//

import SwiftUI

/// The circular gauge SBU drew for state of charge and for the trip dials:
/// a grey track with a rounded progress arc starting at twelve o'clock.
struct RingGauge<Label: View>: View {
    var fraction: Double
    var tint: Color
    var lineWidth: CGFloat = 12
    /// Renders the progress arc itself — not the grey track, not a backing disc —
    /// as tinted Liquid Glass on iOS 26. Off by default: the three trip dials sit
    /// side by side and keep the flat look SBU had.
    var glassArc: Bool = false
    @ViewBuilder var label: Label

    private var clampedFraction: Double { max(0, min(fraction, 1)) }

    /// The stroked, rotated arc as geometry rather than a coloured View: reused to
    /// draw the plain arc and, on iOS 26, as the exact mask the glass material is
    /// clipped to, so the glass follows the arc and not its bounding circle.
    private var arcOutline: some Shape {
        Circle()
            .trim(from: 0, to: clampedFraction)
            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .rotation(.degrees(-90))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.gray.opacity(0.3), lineWidth: lineWidth)
            arc
            label
        }
        .animation(.easeInOut(duration: 0.4), value: fraction)
    }

    @ViewBuilder
    private var arc: some View {
        if glassArc, #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular.tint(tint), in: arcOutline)
        } else {
            arcOutline.foregroundColor(tint)
        }
    }
}

extension Color {
    /// The overview thresholds: red below 10 %, yellow below 25 %, green above.
    static func stateOfChargeOverview(_ percent: Int) -> Color {
        percent < 10 ? .red : percent < 25 ? .yellow : .green
    }

    /// The trip list uses a slightly different second threshold than the overview.
    static func stateOfChargeTrip(_ percent: Int) -> Color {
        percent < 10 ? .red : percent < 30 ? .yellow : .green
    }

    /// The indicator beside the pack's hottest sensor.
    ///
    /// Blue below freezing, which is its own kind of wrong rather than merely cold:
    /// charging there plates lithium onto the anode instead of into it, and the pack
    /// does not get that capacity back. Green through the range a pack is happy
    /// working in, yellow where it is working hard, and red approaching the fifties,
    /// which is about where a JBD pack's over-temperature protections are usually set.
    static func packTemperature(_ celsius: Double) -> Color {
        switch celsius {
        case ..<0: .blue
        case ..<35: .green
        case ..<45: .yellow
        default: .red
        }
    }
}
