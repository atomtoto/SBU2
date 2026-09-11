//
//  DeviceIconView.swift
//  SBU2
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Draws whichever of the three kinds of icon a device has been given.
///
/// `size` is the point size a symbol would be set at. The other two are nudged up
/// from it: an emoji drawn at a symbol's size reads noticeably smaller than the
/// symbol next to it, because the glyph does not fill its own em square.
struct DeviceIconView: View {
    let icon: DeviceIcon
    var size: CGFloat = 17

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size))
                .foregroundStyle(Color.accentColor)
        case .emoji(let text):
            Text(text)
                .font(.system(size: size * 1.15))
        case .glyph(let data):
            GlyphIcon(data: data, size: size * 1.3)
        }
    }
}

/// A Genmoji, which is an image rather than a character.
private struct GlyphIcon: View {
    let data: Data
    let size: CGFloat

    var body: some View {
        #if canImport(UIKit)
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            // The data is only ever what the keyboard handed over, so this is the
            // "written by a newer OS than can read it back" case.
            Image(systemName: "questionmark.square.dashed")
                .font(.system(size: size))
                .foregroundStyle(.secondary)
        }
        #else
        Image(systemName: "questionmark.square.dashed")
            .font(.system(size: size))
            .foregroundStyle(.secondary)
        #endif
    }
}
