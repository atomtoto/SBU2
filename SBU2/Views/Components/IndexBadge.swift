//
//  IndexBadge.swift
//  SBU2
//

import SwiftUI

/// Small numbered circle marking a cell or a temperature probe.
struct IndexBadge: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.caption.monospacedDigit())
            .frame(width: 24, height: 24)
            .background(.quaternary, in: Circle())
            .accessibilityHidden(true)
    }
}
