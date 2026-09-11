//
//  CellVoltageBox.swift
//  SBU2
//
//  The per-cell voltages, in any of the three styles they can be drawn in.
//

import SwiftUI

/// Every populated cell's voltage, with the weakest and strongest picked out.
///
/// Long-press to change the layout. A pack of four cells and a pack of twenty-four
/// want very different things here, which is why the choice starts out automatic:
/// past twenty cells a bar each stops being something anyone can read, and the
/// figures on their own say more.
struct CellVoltageBox: View {
    let voltages: [Double]
    let balancing: Set<Int>
    let summary: CellSummary?
    let emptyMillivolts: Double
    let fullMillivolts: Double

    @Environment(AppSettings.self) private var appSettings

    /// One populated cell. A struct rather than a tuple so `ForEach` has something
    /// to identify rows by when unpopulated cells are filtered out.
    private struct Cell: Identifiable {
        var index: Int
        var voltage: Double
        var id: Int { index }
    }

    var body: some View {
        @Bindable var appSettings = appSettings

        Card {
            switch appSettings.cellVoltageStyle(cellCount: cells.count) {
            case .bars: barsLayout
            case .compact: compactLayout
            case .aesthetic: aestheticLayout
            }
        }
        .animation(.easeInOut(duration: 0.4), value: summary?.lowestIndex)
        .animation(.easeInOut(duration: 0.4), value: summary?.highestIndex)
        .contextMenu {
            Picker("Cell voltage style", selection: $appSettings.storedCellVoltageStyle) {
                Label("Automatic", systemImage: "wand.and.rays")
                    .tag(CellVoltageStyle?.none)
                ForEach(CellVoltageStyle.allCases) { style in
                    Label(style.label, systemImage: style.symbol)
                        .tag(CellVoltageStyle?.some(style))
                }
            }
        }
    }

    // MARK: - A bar per cell

    private var barsLayout: some View {
        // A grid, not a stack of HStacks: every column is as wide as the widest
        // cell in it, on every row, so the bars all start at the same place and
        // sit on their own row's baseline. The old layout left the bar to fight
        // two spacers for the leftover width and then pushed it 6pt down, which
        // is why the bars looked like they belonged to the row below.
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(cells) { cell in
                GridRow {
                    Image(systemName: symbol(for: cell.index))
                        .frame(width: 20, height: 20, alignment: .center)
                        .rotationEffect(.degrees(-90))
                    CircleNumber(number: cell.index + 1)
                    Text(cell.voltage.formatted(decimals: 3, unit: "V"))
                        .monospacedDigit()
                        .foregroundStyle(tint(for: cell.index))
                    Image(systemName: "bolt.fill")
                        .frame(width: 20, height: 20)
                        .opacity(balancing.contains(cell.index) ? 1 : 0)
                        .animation(.easeIn(duration: 0.4), value: balancing.contains(cell.index))
                    LinearMeter(fraction: fraction(for: cell.voltage),
                                tint: .accentColor,
                                height: 11)
                        .frame(minWidth: 60)
                }
            }
        }
    }

    // MARK: - Figures only

    private var compactLayout: some View {
        // As many columns as the width allows rather than a fixed number, so the
        // same layout serves a four-cell pack and a thirty-two-cell one.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)],
                  alignment: .leading,
                  spacing: 8) {
            ForEach(cells) { cell in
                HStack(spacing: 5) {
                    Text("\(cell.index + 1)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(minWidth: 18, alignment: .trailing)
                    Text(cell.voltage.formatted(decimals: 3, unit: "V"))
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(tint(for: cell.index))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                        .opacity(balancing.contains(cell.index) ? 1 : 0)
                        .animation(.easeIn(duration: 0.4), value: balancing.contains(cell.index))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Wide bars, figures floating on top

    private var aestheticLayout: some View {
        VStack(spacing: 8) {
            ForEach(cells) { cell in
                LinearMeter(fraction: fraction(for: cell.voltage),
                            tint: barTint(for: cell.index),
                            height: 38,
                            glass: true) {
                    HStack(spacing: 6) {
                        Text("\(cell.index + 1)")
                            .font(.system(size: 13, weight: .heavy))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        if balancing.contains(cell.index) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 11))
                                .transition(.scale.combined(with: .opacity))
                        }
                        Spacer(minLength: 8)
                        GlassReadout(text: cell.voltage.formatted(decimals: 3, unit: "V"),
                                     tint: tint(for: cell.index))
                    }
                    .padding(.horizontal, 10)
                    .animation(.easeIn(duration: 0.4), value: balancing.contains(cell.index))
                }
            }
        }
    }

    // MARK: - Shared figures

    private var cells: [Cell] {
        voltages.enumerated().compactMap { index, voltage in
            voltage > 0 ? Cell(index: index, voltage: voltage) : nil
        }
    }

    private func symbol(for index: Int) -> String {
        guard let summary else { return "battery.50" }
        if index == summary.lowestIndex { return "battery.25" }
        if index == summary.highestIndex { return "battery.75" }
        return "battery.50"
    }

    /// Red on the weakest cell, green on the strongest — the two the balancer works
    /// on. Nothing is tinted while every cell reads the same, so a pack at rest does
    /// not pick an arbitrary pair.
    private func tint(for index: Int) -> Color {
        guard let summary, summary.highest > summary.lowest else { return .primary }
        if index == summary.lowestIndex { return .red }
        if index == summary.highestIndex { return .green }
        return .primary
    }

    /// The same pairing carried into the bar itself, where `.primary` would be a
    /// slab of black or white rather than a colour.
    private func barTint(for index: Int) -> Color {
        guard let summary, summary.highest > summary.lowest else { return .accentColor }
        if index == summary.lowestIndex { return .red }
        if index == summary.highestIndex { return .green }
        return .accentColor
    }

    private func fraction(for voltage: Double) -> Double {
        let span = fullMillivolts - emptyMillivolts
        guard span > 0 else { return 0 }
        return max(0, min((voltage * 1000 - emptyMillivolts) / span, 1))
    }
}

/// A figure lifted off whatever it is sitting on, so it stays readable against both
/// the filled and the empty half of a bar.
private struct GlassReadout: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background { surface }
    }

    @ViewBuilder
    private var surface: some View {
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: Capsule())
        } else {
            Capsule().fill(.ultraThinMaterial)
        }
    }
}
