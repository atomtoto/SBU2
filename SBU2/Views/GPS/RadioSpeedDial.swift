import SwiftUI

/// A radio scale that starts at zero, then scrolls beneath its centred indicator.
struct RadioSpeedDial: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var indicatorNudge = 0.0
    @State private var nudgeGeneration = 0

    let speed: Double
    let unit: String
    let maximum: Double
    let indicatorStyle: RadioSpeedIndicatorStyle
    let powerText: String?
    let powerFraction: Double
    let isCharging: Bool
    let rangeText: String?
    let onEdit: () -> Void

    private var safeSpeed: Double { speed.isFinite ? max(speed, 0) : 0 }
    private var scaleMaximum: Double { maximum.isFinite ? max(maximum, 1) : 80 }
    private var scaleLowerBound: Double { max(0, safeSpeed - scaleMaximum / 2) }
    private var baseIndicatorFraction: Double {
        min(max((safeSpeed - scaleLowerBound) / scaleMaximum, 0), 1)
    }
    private var indicatorFraction: Double {
        min(max(baseIndicatorFraction + indicatorNudge, 0), 1)
    }
    private var powerTint: Color { isCharging ? .purple : .blue }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Speed", systemImage: "location.fill")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Edit dials")
            }

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(safeSpeed, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 58, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(unit)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Speed")
            .accessibilityValue("\(safeSpeed.formatted(.number.precision(.fractionLength(0)))) \(unit)")

            scale
                .accessibilityHidden(true)

            if powerText != nil || rangeText != nil {
                Divider()
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) { readouts }
                    VStack(alignment: .leading, spacing: 16) { readouts }
                }
            }
        }
        .foregroundStyle(.primary)
        .onChange(of: safeSpeed) { oldSpeed, newSpeed in
            updateIndicatorNudge(from: oldSpeed, to: newSpeed)
        }
    }

    private var scale: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 16
            let width = max(geometry.size.width - inset * 2, 0)
            let x = inset + width * indicatorFraction

            ZStack(alignment: .topLeading) {
                scaleFill(x: x, inset: inset)

                ScrollingSpeedScale(lowerBound: scaleLowerBound,
                                    span: scaleMaximum,
                                    inset: inset)

                speedIndicator(x: x)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: safeSpeed)
        }
        .frame(height: 94)
    }

    @ViewBuilder
    private func scaleFill(x: CGFloat, inset: CGFloat) -> some View {
        switch indicatorStyle {
        case .glassNeedle:
            Rectangle()
                .fill(Color.accentColor.opacity(0.08))
                .frame(width: max(x - inset, 0), height: 46)
                .offset(x: inset, y: 16)

        case .growingBar:
            Rectangle()
                .fill(Color.accentColor.opacity(0.48))
                .frame(width: max(x - inset, 0), height: 46)
                .offset(x: inset, y: 16)

        case .simpleNeedle:
            EmptyView()
        }
    }

    @ViewBuilder
    private func speedIndicator(x: CGFloat) -> some View {
        switch indicatorStyle {
        case .glassNeedle:
            // Keep the needle crisp and put Liquid Glass where it has enough
            // surface to refract visibly: in the round handle at its top.
            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 2, height: 54)
                    .offset(y: 9)
                Color.clear
                    .glassEffect(.regular.tint(Color.accentColor.opacity(0.3)), in: Circle())
                    .frame(width: 18, height: 18)
                    .shadow(color: Color.accentColor.opacity(0.18), radius: 4, y: 2)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 4, height: 4)
                    .offset(y: 7)
            }
            .frame(width: 20, height: 64)
            .offset(x: x - 10, y: 5)

        case .growingBar:
            EmptyView()

        case .simpleNeedle:
            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 62)
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.accentColor)
                    .offset(y: -4)
            }
            .frame(width: 16, height: 64)
            .offset(x: x - 8, y: 5)
        }
    }

    private func updateIndicatorNudge(from oldSpeed: Double, to newSpeed: Double) {
        guard !reduceMotion else {
            indicatorNudge = 0
            return
        }

        let delta = newSpeed - oldSpeed
        guard abs(delta) > 0.1 else { return }

        nudgeGeneration += 1
        let generation = nudgeGeneration
        let impulse = min(max(delta / scaleMaximum, -0.035), 0.035)

        withAnimation(.snappy(duration: 0.18)) {
            indicatorNudge = impulse
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            guard generation == nudgeGeneration else { return }
            withAnimation(.easeOut(duration: 0.35)) {
                indicatorNudge = 0
            }
        }
    }

    @ViewBuilder private var readouts: some View {
        if let powerText {
            VStack(alignment: .leading, spacing: 8) {
                Label(isCharging ? "Charging" : "Power",
                      systemImage: isCharging ? "arrow.down.left" : "bolt.fill")
                    .font(.caption).foregroundStyle(.secondary)
                Text(powerText)
                    .font(.title3.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(powerTint)
                GeometryReader { geometry in
                    Capsule().fill(.quaternary)
                        .overlay(alignment: .leading) {
                            Capsule().fill(powerTint)
                                .frame(width: geometry.size.width * min(max(powerFraction.isFinite ? powerFraction : 0, 0), 1))
                        }
                }
                .frame(height: 5)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        if let rangeText {
            VStack(alignment: .leading, spacing: 8) {
                Label("Remaining", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.caption).foregroundStyle(.secondary)
                Text(rangeText)
                    .font(.title3.weight(.semibold)).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Its lower bound is animatable so the ticks themselves glide instead of merely
/// replacing their labels when a new GPS sample arrives.
private struct ScrollingSpeedScale: View, Animatable {
    var lowerBound: Double
    let span: Double
    let inset: CGFloat

    var animatableData: Double {
        get { lowerBound }
        set { lowerBound = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let width = max(size.width - inset * 2, 0)
            let tickStep = span / 40
            let firstTick = max(Int(floor(lowerBound / tickStep)) - 1, 0)
            let lastTick = Int(ceil((lowerBound + span) / tickStep)) + 1

            for tick in firstTick...lastTick {
                let value = Double(tick) * tickStep
                let position = (value - lowerBound) / span
                guard position >= 0, position <= 1 else { continue }

                let major = tick.isMultiple(of: 10)
                let medium = tick.isMultiple(of: 5)
                let tickX = inset + width * position
                let height: CGFloat = major ? 34 : (medium ? 25 : 15)
                let path = Path { path in
                    path.move(to: CGPoint(x: tickX, y: 22))
                    path.addLine(to: CGPoint(x: tickX, y: 22 + height))
                }
                context.stroke(path,
                               with: .color(Color.primary.opacity(major ? 0.65 : 0.22)),
                               lineWidth: major ? 1.5 : 1)
                if major {
                    let decimals = value.rounded() == value ? 0 : 1
                    let label = Text(value.formatted(
                        .number.precision(.fractionLength(decimals))))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    context.draw(label, at: CGPoint(x: tickX, y: size.height - 8))
                }
            }
        }
    }
}

#Preview("Radio • cruising") {
    RadioSpeedDial(speed: 37, unit: "km/h", maximum: 80, indicatorStyle: .glassNeedle,
                   powerText: "−840 W", powerFraction: 0.84, isCharging: false,
                   rangeText: "42 km", onEdit: {})
        .padding()
}

#Preview("Radio • charging / imperial") {
    RadioSpeedDial(speed: 18, unit: "mph", maximum: 60, indicatorStyle: .growingBar,
                   powerText: "240 W", powerFraction: 0.24, isCharging: true,
                   rangeText: nil, onEdit: {})
        .padding()
        .preferredColorScheme(.dark)
}
