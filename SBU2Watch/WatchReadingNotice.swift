import SwiftUI

/// Keeps an old reading visibly marked wherever the user drills into it.
struct WatchReadingNotice: View {
    @Environment(BMSConnection.self) private var connection

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if !connection.hasReading {
                Label("Waiting for BMS readings", systemImage: "dot.radiowaves.left.and.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if connection.hasFreshReading() {
                Label("Live data", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            } else {
                Label("Data outdated", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }
}
