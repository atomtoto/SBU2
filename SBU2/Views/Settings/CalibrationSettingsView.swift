//
//  CalibrationSettingsView.swift
//  SBU2
//

import SwiftUI

/// Tells the pack what its readings should really be.
///
/// Every row here writes to the BMS. The figures are the ones *you* measured with
/// something you trust — the pack works out its own correction from them — so a
/// figure typed in carelessly is not a display glitch: it moves the point at which
/// the pack protects itself.
struct CalibrationSettingsView: View {
    @Environment(BMSConnection.self) private var connection

    /// Keyed by the row that owns it, so each field keeps its own text.
    @State private var entries: [String: String] = [:]
    @State private var confirming: BMSCalibration?

    private var unit: UnitTemperature { Locale.current.preferredTemperatureUnit }

    var body: some View {
        Form {
            Section {
                Label("These write to the battery, not to the app.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote.weight(.semibold))
                Text("""
                     The BMS decides when to cut the current from what it *thinks* it \
                     is measuring. Calibrating tells it what a reading should really \
                     be, so a figure that is wrong here makes every protection that \
                     depends on it fire at the wrong moment — or not at all. An \
                     over-voltage limit set at 3.65 V does nothing useful if the pack \
                     has been taught to read a full cell as 3.40 V.

                     Only enter figures you have just measured, on a meter you trust, \
                     while the pack is settled. If you have nothing to measure with, \
                     there is nothing to gain here: leave it alone.
                     """)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Before you start")
            }

            if !connection.cellVoltages.isEmpty {
                Section {
                    ForEach(liveCells) { cell in
                        CalibrationRow(title: "Cell \(cell.index + 1)",
                                       reading: cell.voltage.formatted(decimals: 3, unit: "V"),
                                       placeholder: String(format: "%.0f", cell.voltage * 1000),
                                       suffix: "mV",
                                       text: binding("cell\(cell.index)"),
                                       isEnabled: connection.canCalibrate,
                                       calibration: cellCalibration(for: cell.index)) {
                            confirming = $0
                        }
                    }
                } header: {
                    Text("Cell voltages")
                } footer: {
                    Text("Measure at the cell's own terminals, in millivolts — 3300, not 3.3. The pack must be resting: current flowing anywhere in the string drags the reading with it.")
                }
            }

            if !connection.info.temperatures.isEmpty {
                Section {
                    ForEach(liveSensors) { sensor in
                        CalibrationRow(title: "Sensor \(sensor.index + 1)",
                                       reading: connection.info.temperatureText(sensor.celsius),
                                       placeholder: String(format: "%.1f", converted(sensor.celsius)),
                                       suffix: unit.symbol,
                                       text: binding("ntc\(sensor.index)"),
                                       isEnabled: connection.canCalibrate,
                                       calibration: temperatureCalibration(for: sensor.index)) {
                            confirming = $0
                        }
                    }
                } header: {
                    Text("Temperatures")
                } footer: {
                    Text("Measure against the sensor itself, once it has had time to settle at the same temperature as whatever it is stuck to.")
                }
            }

            Section {
                Button("Zero the current reading") {
                    confirming = .idleCurrent
                }
                .disabled(!connection.canCalibrate)

                CalibrationRow(title: "Charging",
                               reading: connection.info.currentText,
                               placeholder: "10.0",
                               suffix: "A",
                               text: binding("charge"),
                               isEnabled: connection.canCalibrate,
                               calibration: currentCalibration(charging: true)) {
                    confirming = $0
                }
                CalibrationRow(title: "Discharging",
                               reading: connection.info.currentText,
                               placeholder: "10.0",
                               suffix: "A",
                               text: binding("discharge"),
                               isEnabled: connection.canCalibrate,
                               calibration: currentCalibration(charging: false)) {
                    confirming = $0
                }
            } header: {
                Text("Current")
            } footer: {
                Text("Zero it with nothing connected and nothing flowing — that one needs no figure. The two below need a clamp meter on the pack lead and a steady current actually running in that direction; enter what the meter reads, without its sign.")
            }

            if connection.isCalibrating {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Writing to the BMS…")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            switch connection.calibrationOutcome {
            case .succeeded:
                Section {
                    Label("The BMS accepted the calibration.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            case .rejected(let message):
                Section {
                    Label(message, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            case .idle:
                EmptyView()
            }
        }
        .navigationTitle("Calibration")
        .navigationBarTitleDisplayMode(.inline)
        .dismissableKeyboard()
        .confirmationDialog(confirming.map(title(for:)) ?? "",
                            isPresented: Binding(get: { confirming != nil },
                                                 set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible) {
            if let calibration = confirming {
                Button("Write it to the BMS", role: .destructive) {
                    connection.calibrate(calibration)
                    confirming = nil
                }
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: {
            Text("The pack will trust this figure over its own reading from now on, and the protections that depend on it move with it. It can be corrected later, but there is no undo.")
        }
    }

    // MARK: - Rows

    /// Structs rather than tuples so `ForEach` has a plain `id` to key rows by.
    private struct LiveCell: Identifiable {
        let index: Int
        let voltage: Double
        var id: Int { index }
    }

    private struct LiveSensor: Identifiable {
        let index: Int
        let celsius: Double
        var id: Int { index }
    }

    private var liveCells: [LiveCell] {
        connection.cellVoltages.enumerated().compactMap { index, voltage in
            voltage > 0 ? LiveCell(index: index, voltage: voltage) : nil
        }
    }

    private var liveSensors: [LiveSensor] {
        connection.info.temperatures.enumerated().map { LiveSensor(index: $0.offset, celsius: $0.element) }
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding { entries[key] ?? "" } set: { entries[key] = $0 }
    }

    private func converted(_ celsius: Double) -> Double {
        Measurement(value: celsius, unit: UnitTemperature.celsius).converted(to: unit).value
    }

    // MARK: - What each row would write

    private func cellCalibration(for index: Int) -> BMSCalibration? {
        guard let millivolts = Int(entries["cell\(index)"]?.trimmingCharacters(in: .whitespaces) ?? "")
        else { return nil }
        return .cell(index: index, millivolts: millivolts)
    }

    private func temperatureCalibration(for index: Int) -> BMSCalibration? {
        guard let value = Double(decimal: entries["ntc\(index)"]) else { return nil }
        let celsius = Measurement(value: value, unit: unit)
            .converted(to: UnitTemperature.celsius).value
        return .temperature(index: index, celsius: celsius)
    }

    private func currentCalibration(charging: Bool) -> BMSCalibration? {
        guard let amperes = Double(decimal: entries[charging ? "charge" : "discharge"]) else { return nil }
        return charging ? .chargeCurrent(amperes: amperes) : .dischargeCurrent(amperes: amperes)
    }

    private func title(for calibration: BMSCalibration) -> String {
        switch calibration {
        case .cell(let index, _): "Calibrate cell \(index + 1)?"
        case .temperature(let index, _): "Calibrate sensor \(index + 1)?"
        case .idleCurrent: "Zero the current reading?"
        case .chargeCurrent: "Calibrate the charging current?"
        case .dischargeCurrent: "Calibrate the discharging current?"
        }
    }
}

/// What the pack reads now, what it should read, and the button that says so.
private struct CalibrationRow: View {
    let title: String
    let reading: String
    let placeholder: String
    let suffix: String
    @Binding var text: String
    let isEnabled: Bool
    /// `nil` when the field is empty or not a number.
    let calibration: BMSCalibration?
    let onCalibrate: (BMSCalibration) -> Void

    private var isReady: Bool {
        guard let calibration else { return false }
        return isEnabled && calibration.isPlausible
    }

    /// Only complains once there is something to complain about — an empty field is
    /// not a mistake, a figure outside the sane range is.
    private var isOutOfRange: Bool {
        guard let calibration else { return false }
        return !calibration.isPlausible
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(reading)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                TextField(placeholder, text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                Text(suffix)
                    .foregroundStyle(.secondary)
                Button("Calibrate") {
                    if let calibration { onCalibrate(calibration) }
                }
                .buttonStyle(.bordered)
                .disabled(!isReady)
            }
            if isOutOfRange {
                Text("That is outside anything a pack reads. Check the figure.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }
}

private extension Double {
    /// Accepts a comma as the decimal mark, which is what the number pad offers on a
    /// French keyboard.
    init?(decimal text: String?) {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        self.init(text.replacingOccurrences(of: ",", with: "."))
    }
}
