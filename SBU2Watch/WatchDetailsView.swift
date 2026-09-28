import SwiftUI

struct WatchDetailsView: View {
    @Environment(BMSConnection.self) private var connection

    var body: some View {
        let info = connection.info
        List {
            Section("Battery") {
                LabeledContent("Capacity", value: info.residualCapacity.formatted(decimals: 1, unit: "Ah"))
                LabeledContent("Cycles", value: "\(info.cycles)")
                LabeledContent("Charge MOS", value: info.chargeMOSEnabled ? "On" : "Off")
                LabeledContent("Discharge MOS", value: info.dischargeMOSEnabled ? "On" : "Off")
            }

            if !info.temperatures.isEmpty {
                Section("Temperatures") {
                    ForEach(Array(info.temperatures.enumerated()), id: \.offset) { index, temperature in
                        LabeledContent("Sensor \(info.temperatureLabel(index))", value: info.temperatureText(temperature))
                    }
                }
            }

            if !info.protections.isEmpty {
                Section("Active alerts") {
                    ForEach(info.protections.sorted(by: { $0.rawValue < $1.rawValue })) { protection in
                        Label(protection.label, systemImage: protection.symbol)
                            .foregroundStyle(protection.tint)
                    }
                }
            }
        }
        .navigationTitle("Details")
    }
}
