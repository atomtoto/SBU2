//
//  CellVoltageBox.swift
//  SBU2
//
//  The per-cell voltages, in any of the four styles they can be drawn in.
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
    /// This pack's own settings: the style it is drawn in, and the two voltages the
    /// bars are scaled between.
    @Binding var settings: DeviceSettings

    /// One populated cell. A struct rather than a tuple so `ForEach` has something
    /// to identify rows by when unpopulated cells are filtered out.
    private struct Cell: Identifiable {
        var index: Int
        var voltage: Double
        var id: Int { index }
    }

    var body: some View {
        Card {
            switch settings.cellVoltageStyle(cellCount: cells.count) {
            case .bars: barsLayout
            case .compact: compactLayout
            case .compactAesthetic: compactAestheticLayout
            case .aesthetic: aestheticLayout
            }
        }
        .animation(.easeInOut(duration: 0.4), value: summary?.lowestIndex)
        .animation(.easeInOut(duration: 0.4), value: summary?.highestIndex)
        .contextMenu {
            Picker("Cell voltage style", selection: $settings.storedCellVoltageStyle) {
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
                aestheticRow(cell, height: 38, compact: false)
            }
        }
    }

    /// The same bars, two to a row and a little shorter, so a longer string of cells
    /// fits on a screen without giving any of them up.
    private var compactAestheticLayout: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                  spacing: 8) {
            ForEach(cells) { cell in
                aestheticRow(cell, height: 30, compact: true)
            }
        }
    }

    /// One cell as a bar with its figure floating on top.
    ///
    /// The bar is plain colour rather than glass: the figure on top is the glass, and
    /// two layers of it stacked read as neither.
    private func aestheticRow(_ cell: Cell, height: CGFloat, compact: Bool) -> some View {
        LinearMeter(fraction: fraction(for: cell.voltage),
                    tint: .accentColor,
                    height: height) {
            HStack(spacing: compact ? 4 : 6) {
                if figuresLead {
                    readout(cell, compact: compact)
                    Spacer(minLength: 6)
                    indexLabel(cell, compact: compact)
                } else {
                    indexLabel(cell, compact: compact)
                    Spacer(minLength: 6)
                    readout(cell, compact: compact)
                }
            }
            .padding(.horizontal, compact ? 7 : 10)
            .animation(.easeIn(duration: 0.4), value: balancing.contains(cell.index))
        }
    }

    private func indexLabel(_ cell: Cell, compact: Bool) -> some View {
        HStack(spacing: 3) {
            Text("\(cell.index + 1)")
                .font(.system(size: compact ? 11 : 13, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if balancing.contains(cell.index) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: compact ? 9 : 11))
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private func readout(_ cell: Cell, compact: Bool) -> some View {
        GlassReadout(text: cell.voltage.formatted(decimals: 3, unit: "V"),
                     tint: tint(for: cell.index),
                     compact: compact)
    }

    /// Which side the figures sit on.
    ///
    /// A bar fills from the left, so a pack sitting above its nominal cell voltage
    /// has the left of every bar covered and the right of it bare, and a pack below
    /// nominal has that the other way round. Putting the figures on whichever side is
    /// uniformly one thing keeps them off the edge between the two, rather than
    /// leaving them half on the fill and half off it — and keeps them on the same
    /// side as each other, since one average decides it for the whole box.
    private var figuresLead: Bool {
        guard let summary else { return true }
        return summary.average >= Double(settings.cellNominalVoltage) / 1000
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

    private func fraction(for voltage: Double) -> Double {
        let empty = Double(settings.cellEmptyVoltage)
        let span = Double(settings.cellFullVoltage) - empty
        guard span > 0 else { return 0 }
        return max(0, min((voltage * 1000 - empty) / span, 1))
    }
}

/// A figure lifted off whatever it is sitting on, so it stays readable against both
/// the filled and the empty half of a bar.
private struct GlassReadout: View {
    let text: String
    let tint: Color
    var compact: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: compact ? 12 : 14, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, compact ? 7 : 10)
            .padding(.vertical, compact ? 3 : 5)
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
