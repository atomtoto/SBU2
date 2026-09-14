//
//  IndicatorLight.swift
//  SBU2
//

import SwiftUI

/// A small coloured light, haloed so it reads as an indicator rather than as a
/// bullet point in front of the figure.
///
/// It began on the GPS screen, beside the pack's hottest reading, and now says the
/// same thing beside every temperature in the overview: the colour is the reading's
/// own verdict on itself, which a figure in degrees does not give anybody who does not
/// already know what a good one looks like.
struct IndicatorLight: View {
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
