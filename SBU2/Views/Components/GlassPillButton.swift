//
//  GlassPillButton.swift
//  SBU2
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The pill-shaped, tap-to-act button SBU2 uses wherever a single command needs a
/// prominent, colour-coded control: the charge/discharge MOSFET toggles in
/// Overview, and the trip reset button in GPS. Sharing this one view keeps every
/// such button the same size, shape and haptic — only the colour, symbol and title
/// are meant to vary.
struct GlassPillButton: View {

    /// How large the pill is drawn.
    ///
    /// Only the drawing changes: the tap target stays 44pt tall either way, which is
    /// Apple's minimum comfortable one and the reason SBU's 35 was worth leaving
    /// behind. A small pill is for a button sitting among rows of text rather than
    /// standing on its own.
    enum Size {
        case standard, small

        var width: CGFloat { self == .standard ? 152 : 124 }
        var height: CGFloat { self == .standard ? 44 : 36 }
        var cornerRadius: CGFloat { self == .standard ? 22 : 18 }
        var fontSize: CGFloat { self == .standard ? 17 : 15 }
        var symbolSlot: CGFloat { self == .standard ? 24 : 20 }
    }

    let title: String
    let color: Color
    let symbol: String
    /// This button is the one waiting for a result to come back.
    var isWaiting: Bool = false
    /// Either sibling button is waiting, so neither accepts a tap.
    var isBusy: Bool = false
    var size: Size = .standard
    let action: () -> Void

    var body: some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            action()
        } label: {
            ZStack {
                background
                    .frame(width: size.width, height: size.height)
                HStack {
                    Text(title)
                        .font(.system(size: size.fontSize))
                    // A fixed slot sized to the symbol, so swapping it for the
                    // spinner neither shifts the label nor changes apparent size.
                    ZStack {
                        if isWaiting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .transition(.opacity.combined(with: .scale(scale: 0.6)))
                        } else {
                            Image(systemName: symbol)
                                .transition(.opacity.combined(with: .scale(scale: 0.6)))
                        }
                    }
                    .frame(width: size.symbolSlot, height: size.symbolSlot)
                }
                .foregroundColor(.white)
            }
            // However small the pill is drawn, it stays as easy to hit.
            .frame(height: max(size.height, 44))
            .contentShape(.rect)
        }
        // Blocking hit testing rather than .disabled keeps the spinner at full
        // strength while the button is unavailable.
        .allowsHitTesting(!isBusy)
        .opacity(isBusy && !isWaiting ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.2), value: isWaiting)
        .animation(.easeInOut(duration: 0.2), value: isBusy)
        .accessibilityLabel(title)
        .accessibilityValue(isWaiting ? "Waiting for the BMS" : "")
    }

    /// Liquid Glass on iOS 26, tinted by the same colour the flat fallback uses, so
    /// the on/off/gray/blue meaning survives either way.
    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: size.cornerRadius)
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular.tint(color), in: shape)
        } else {
            shape.fill(color)
        }
    }
}
