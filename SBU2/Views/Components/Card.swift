//
//  Card.swift
//  SBU2
//

import SwiftUI

/// The rounded panel every overview section sits in.
///
/// On iOS 26 it uses Liquid Glass; below that it falls back to the material SBU used,
/// so the layout is identical and only the surface changes.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity)
            .modifier(CardSurface())
    }
}

private struct CardSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(in: .rect(cornerRadius: 26))
        } else {
            content.background(.ultraThinMaterial,
                               in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }
}

/// Section heading used inside cards, matching the weight of a grouped list header.
struct CardHeader: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
        .foregroundStyle(.secondary)
    }
}
