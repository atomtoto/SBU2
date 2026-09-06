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
        ZStack {
            Circle()
                .foregroundColor(Color(uiColor: .tertiarySystemBackground))
            Text("\(number)")
        }
        .frame(width: 25, height: 25, alignment: .center)
        .aspectRatio(1, contentMode: .fit)
    }
}
