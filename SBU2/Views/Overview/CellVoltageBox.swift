//
//  CellVoltageBox.swift
//  SBU2
//
//  The per-cell figures, in any of the four styles and either of the two readouts.
//

import SwiftUI

/// Which per-cell figure the box is showing.
enum CellReadout: String, CaseIterable, Identifiable {
    case voltages, resistances

    var id: Self { self }

    var label: String {
        switch self {
        case .voltages: return "Voltages"
        case .resistances: return "Resistances"
        }
    }
}

/// Every populated cell, with the two ends of the string picked out.
///
/// Long-press to change the layout. A pack of four cells and a pack of twenty-four
/// want very different things here, which is why the choice starts out automatic:
/// past twenty cells a bar each stops being something anyone can read, and the
/// figures on their own say more.
///
/// A pack that measures its own wiring gets a second readout, and a picker under the
/// figures to swap between them. That readout says something quite different from the
/// voltages: a cell standing out there is a connection to go and check — a lead, a
/// crimp, a terminal — rather than a cell going bad.
struct CellVoltageBox: View {
    let voltages: [Double]
    /// Empty on a family that does not measure it, which is what the picker is
    /// shown or hidden on.
    var resistances: [Double] = []
    let balancing: Set<Int>
    let summary: CellSummary?
    /// This pack's own settings: the style it is drawn in, and the two voltages the
    /// bars are scaled between.
    @Binding var settings: DeviceSettings

    /// Not stored with the rest of the settings on purpose: the voltages are what
    /// anybody opens this screen for, and the resistances are something you go and
    /// look at, not something you want to find still showing next time.
    @State private var readout: CellReadout = .voltages

    /// One populated cell, already turned into everything the layouts need to draw
    /// it. Both readouts produce these, which is what lets one set of layouts serve
    /// the two of them.
    private struct Entry: Identifiable {
        var index: Int
        var text: String
        var fraction: Double
        var tint: Color
        var symbol: String
        var rotatesSymbol: Bool
        var id: Int { index }
    }

    var body: some View {
        Card {
            VStack(spacing: 0) {
                layout
                if offersResistances {
                    Picker("Readout", selection: $readout) {
                        ForEach(CellReadout.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.top, 12)
                }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: summary?.lowestIndex)
        .animation(.easeInOut(duration: 0.4), value: summary?.highestIndex)
        .animation(.easeInOut(duration: 0.25), value: readout)
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

    @ViewBuilder
    private var layout: some View {
        switch settings.cellVoltageStyle(cellCount: entries.count) {
        case .bars: barsLayout
        case .compact: compactLayout
        case .compactAesthetic: compactAestheticLayout
        case .aesthetic: aestheticLayout
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
            ForEach(entries) { entry in
                GridRow {
                    Image(systemName: entry.symbol)
                        .frame(width: 20, height: 20, alignment: .center)
                        .rotationEffect(.degrees(entry.rotatesSymbol ? -90 : 0))
                    CircleNumber(number: entry.index + 1)
                    Text(entry.text)
                        .monospacedDigit()
                        .foregroundStyle(entry.tint)
                    Image(systemName: "bolt.fill")
                        .frame(width: 20, height: 20)
                        .opacity(balancing.contains(entry.index) ? 1 : 0)
                        .animation(.easeIn(duration: 0.4), value: balancing.contains(entry.index))
                    LinearMeter(fraction: entry.fraction, tint: .accentColor, height: 11)
                        .frame(minWidth: 60)
                }
            }
        }
    }

    // MARK: - Figures only

    private var compactLayout: some View {
        // Columns are still fitted to the width rather than fixed, but a short string
        // of cells asks for wider ones and gets a bigger figure in them: four cells
        // spread across three columns left one hanging on a row of its own and set in
        // the smallest type on the screen, which is the opposite of what all that
        // spare width was for.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: compactWidth), spacing: 10)],
                  alignment: .center,
                  spacing: 10) {
            ForEach(entries) { entry in
                HStack(spacing: 5) {
                    Text("\(entry.index + 1)")
                        .font(.system(size: compactFontSize * 0.72, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(entry.text)
                        .font(.system(size: compactFontSize, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(entry.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if balancing.contains(entry.index) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: compactFontSize * 0.72))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeIn(duration: 0.4), value: balancing.contains(entry.index))
                // Centred in its column rather than pushed to the leading edge, so
                // the figures sit evenly across the card instead of drifting left.
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// How much width each figure asks for, and how large it is set.
    ///
    /// Both follow the length of the string rather than a fixed choice: a pack with a
    /// handful of cells has width to spare and should use it, and one with two dozen
    /// needs every column it can get. The two move together because a figure given
    /// more room is only better if it is also easier to read.
    private var compactWidth: CGFloat {
        switch entries.count {
        case ...6: 150
        case ...12: 112
        default: 92
        }
    }

    private var compactFontSize: CGFloat {
        switch entries.count {
        case ...6: 20
        case ...12: 16
        default: 14
        }
    }

    // MARK: - Wide bars, figures floating on top

    private var aestheticLayout: some View {
        VStack(spacing: 8) {
            ForEach(entries) { entry in
                aestheticRow(entry, height: 38, compact: false)
            }
        }
    }

    /// The same bars, two to a row and a little shorter, so a longer string of cells
    /// fits on a screen without giving any of them up.
    private var compactAestheticLayout: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                  spacing: 8) {
            ForEach(entries) { entry in
                aestheticRow(entry, height: 30, compact: true)
            }
        }
    }

    /// One cell as a bar with its figure floating on top.
    ///
    /// The bar is plain colour rather than glass: the figure on top is the glass, and
    /// two layers of it stacked read as neither.
    private func aestheticRow(_ entry: Entry, height: CGFloat, compact: Bool) -> some View {
        LinearMeter(fraction: entry.fraction, tint: .accentColor, height: height) {
            HStack(spacing: compact ? 4 : 6) {
                if figuresLead {
                    glassReadout(entry, compact: compact)
                    Spacer(minLength: 6)
                    indexLabel(entry, compact: compact)
                } else {
                    indexLabel(entry, compact: compact)
                    Spacer(minLength: 6)
                    glassReadout(entry, compact: compact)
                }
            }
            .padding(.horizontal, compact ? 7 : 10)
            .animation(.easeIn(duration: 0.4), value: balancing.contains(entry.index))
        }
    }

    private func indexLabel(_ entry: Entry, compact: Bool) -> some View {
        HStack(spacing: 3) {
            Text("\(entry.index + 1)")
                .font(.system(size: compact ? 11 : 13, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if balancing.contains(entry.index) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: compact ? 9 : 11))
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private func glassReadout(_ entry: Entry, compact: Bool) -> some View {
        GlassReadout(text: entry.text, tint: entry.tint, compact: compact)
    }

    /// Which side the figures sit on.
    ///
    /// A bar fills from the left, so a pack sitting above its nominal cell voltage
    /// has the left of every bar covered and the right of it bare, and a pack below
    /// nominal has that the other way round. Putting the figures on whichever side is
    /// uniformly one thing keeps them off the edge between the two, rather than
    /// leaving them half on the fill and half off it — and keeps them on the same
    /// side as each other, since one average decides it for the whole box.
    ///
    /// It follows the voltages whichever readout is showing, so that swapping between
    /// the two does not throw every figure across its bar.
    private var figuresLead: Bool {
        guard let summary else { return true }
        return summary.average >= Double(settings.cellNominalVoltage) / 1000
    }

    // MARK: - What each readout makes of a cell

    private var offersResistances: Bool { !liveIndices.isEmpty && !resistances.isEmpty }

    private var entries: [Entry] {
        readout == .resistances && offersResistances ? resistanceEntries : voltageEntries
    }

    /// The cells that are actually there. A pack always reports the full width of its
    /// layout, and the ones past the end of the string read zero.
    private var liveIndices: [Int] {
        (0..<min(voltages.count, resistances.count)).filter { voltages[$0] > 0 }
    }

    private var voltageEntries: [Entry] {
        voltages.enumerated().compactMap { index, volts in
            guard volts > 0 else { return nil }
            return Entry(index: index,
                         text: volts.formatted(decimals: 3, unit: "V"),
                         fraction: voltageFraction(volts),
                         tint: voltageTint(index),
                         symbol: voltageSymbol(index),
                         rotatesSymbol: true)
        }
    }

    /// Scaled against the worst one rather than against a fixed span.
    ///
    /// There is no equivalent of the empty and full voltages to measure a resistance
    /// between — what counts as high depends on the lead, the crimp and the pack — so
    /// the bars say how each cell compares with the worst of its own siblings, which
    /// is the comparison actually worth making.
    private var resistanceEntries: [Entry] {
        let live = liveIndices
        let values = live.map { resistances[$0] }
        let worst = values.max() ?? 0
        let best = values.min() ?? 0
        return live.map { index in
            let ohms = resistances[index]
            return Entry(index: index,
                         text: ohms.formatted(decimals: 3, unit: "Ω"),
                         fraction: worst > 0 ? ohms / worst : 0,
                         tint: resistanceTint(ohms, worst: worst, best: best),
                         symbol: "bolt.horizontal",
                         rotatesSymbol: false)
        }
    }

    private func voltageSymbol(_ index: Int) -> String {
        guard let summary else { return "battery.50" }
        if index == summary.lowestIndex { return "battery.25" }
        if index == summary.highestIndex { return "battery.75" }
        return "battery.50"
    }

    /// Red on the weakest cell, green on the strongest — the two the balancer works
    /// on. Nothing is tinted while every cell reads the same, so a pack at rest does
    /// not pick an arbitrary pair.
    private func voltageTint(_ index: Int) -> Color {
        guard let summary, summary.highest > summary.lowest else { return .primary }
        if index == summary.lowestIndex { return .red }
        if index == summary.highestIndex { return .green }
        return .primary
    }

    /// The other way round from the voltages: here the *highest* figure is the bad
    /// one. A cell whose wiring costs more than its neighbours' is a connection worth
    /// going to look at.
    private func resistanceTint(_ ohms: Double, worst: Double, best: Double) -> Color {
        guard worst > best else { return .primary }
        if ohms == worst { return .red }
        if ohms == best { return .green }
        return .primary
    }

    private func voltageFraction(_ volts: Double) -> Double {
        let empty = Double(settings.cellEmptyVoltage)
        let span = Double(settings.cellFullVoltage) - empty
        guard span > 0 else { return 0 }
        return max(0, min((volts * 1000 - empty) / span, 1))
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
