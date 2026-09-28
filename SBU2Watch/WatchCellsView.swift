import SwiftUI

struct WatchCellsView: View {
    @Environment(BMSConnection.self) private var connection

    var body: some View {
        List {
            if connection.cellVoltages.isEmpty {
                ProgressView("Reading cells…")
            }
            if let summary = connection.cellSummary {
                LabeledContent("Spread", value: summary.deltaMillivolts.formatted(decimals: 0, unit: "mV"))
                LabeledContent("Lowest", value: "#\(summary.lowestIndex + 1)")
                LabeledContent("Highest", value: "#\(summary.highestIndex + 1)")
            }
            ForEach(Array(connection.cellVoltages.enumerated()), id: \.offset) { index, voltage in
                HStack {
                    Text("Cell \(index + 1)")
                    Spacer()
                    Text(voltage.formatted(decimals: 3, unit: "V"))
                        .monospacedDigit()
                }
            }
        }
        .navigationTitle("Cells")
    }
}
