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
    let title: String
    let color: Color
    let symbol: String
    /// This button is the one waiting for a result to come back.
    var isWaiting: Bool = false
    /// Either sibling button is waiting, so neither accepts a tap.
    var isBusy: Bool = false
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
                    // 44pt is Apple's minimum comfortable tap target; SBU's 35 was under it.
                    .frame(width: 152, height: 44)
                HStack {
                    Text(title)
                        .font(.system(size: 17))
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
                    .frame(width: 24, height: 24)
                }
                .foregroundColor(.white)
            }
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
        let shape = RoundedRectangle(cornerRadius: 22)
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular.tint(color), in: shape)
        } else {
            shape.fill(color)
        }
    }
}
