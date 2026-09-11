//
//  LinearMeter.swift
//  SBU2
//

import SwiftUI

/// A rounded track with a fill that grows from one end.
///
/// The flat counterpart to `RingGauge`, and the shape the cell bars were already
/// drawing by hand. Which end the fill grows from is a parameter because the power
/// meter uses it to say which way the energy is going: out of the pack fills
/// rightwards, the way a bar normally fills, and into it fills back the other way.
struct LinearMeter<Label: View>: View {
    var fraction: Double
    var tint: Color
    /// The edge the fill is anchored to. `.leading` unless the value means something
    /// that runs the other way.
    var anchor: Alignment = .leading
    var height: CGFloat = 12
    /// Draws the fill as tinted Liquid Glass on iOS 26 rather than as flat colour.
    var glass: Bool = false
    /// Sits on top of the bar, centred. Empty for a plain meter.
    @ViewBuilder var label: Label

    private var clamped: Double { max(0, min(fraction, 1)) }

    var body: some View {
        Capsule()
            .fill(.gray.opacity(0.3))
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay(alignment: anchor) {
                // The track claims the width; the fill reads it back rather than
                // trying to claim any of its own, so the two cannot disagree.
                GeometryReader { geometry in
                    fill
                        .frame(width: geometry.size.width * clamped)
                        .frame(maxWidth: .infinity, alignment: anchor)
                }
            }
            .overlay { label }
            .animation(.easeInOut(duration: 0.4), value: fraction)
    }

    @ViewBuilder
    private var fill: some View {
        if glass, #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular.tint(tint), in: Capsule())
        } else {
            Capsule().fill(tint)
        }
    }
}

extension LinearMeter where Label == EmptyView {
    init(fraction: Double,
         tint: Color,
         anchor: Alignment = .leading,
         height: CGFloat = 12,
         glass: Bool = false) {
        self.init(fraction: fraction,
                  tint: tint,
                  anchor: anchor,
                  height: height,
                  glass: glass) { EmptyView() }
    }
}
