//
//  Card.swift
//  SBU2
//

import SwiftUI

/// The rounded panel every overview and trip section sits in.
///
/// This is SBU's surface, reproduced: a 25pt continuous rounded rectangle filled
/// with `.ultraThinMaterial`. The device list and the settings forms use the
/// system's own materials, so they pick up Liquid Glass on iOS 26 on their own.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
    }
}

/// The numbered circle SBU used beside every cell and temperature probe.
struct CircleNumber: View {
    let number: Int

    var body: some View {
        CircleLabel(text: "\(number)")
    }
}

/// The same circle, for the readings a pack names rather than numbers — a JK pack's
/// third temperature is its MOSFETs, and calling it "3" put it in a series it does
/// not belong to.
struct CircleLabel: View {
    let text: String

    var body: some View {
        ZStack {
            Circle()
                .foregroundColor(Color(uiColor: .tertiarySystemBackground))
            Text(text)
                // A name has to fit the same circle a single digit does.
                .font(text.count > 1 ? .system(size: 10, weight: .semibold) : .body)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 2)
        }
        .frame(width: 25, height: 25, alignment: .center)
        .aspectRatio(1, contentMode: .fit)
    }
}
