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
    @ViewBuilder var label: Label

    var body: some View {
        ZStack {
            Circle()
                .stroke(.gray.opacity(0.3), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(fraction, 1)))
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .rotationEffect(.init(degrees: -90))
                .foregroundColor(tint)
            label
        }
        .animation(.easeInOut(duration: 0.4), value: fraction)
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
}
