//
//  RingGauge.swift
//  SBU2
//

import SwiftUI

/// The circular gauge used for state of charge and for the trip dials.
struct RingGauge<Label: View>: View {
    var fraction: Double
    var tint: Color
    var lineWidth: CGFloat = 12
    @ViewBuilder var label: Label

    var body: some View {
        ZStack {
            Circle()
                .stroke(.tertiary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(fraction, 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .rotationEffect(.degrees(-90))
            label
                .multilineTextAlignment(.center)
                .padding(lineWidth * 1.6)
        }
        .animation(.easeInOut(duration: 0.4), value: fraction)
    }
}

extension Color {
    /// Red below 10 %, amber below 25 %, green above — the thresholds SBU used.
    static func forStateOfCharge(_ percent: Int) -> Color {
        switch percent {
        case ..<10: .red
        case ..<25: .orange
        default: .green
        }
    }
}
