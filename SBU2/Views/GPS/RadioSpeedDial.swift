import SwiftUI

/// A fixed radio scale: the needle tracks speed, never the trip's changing top speed.
struct RadioSpeedDial: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let speed: Double
    let unit: String
    let maximum: Double
    let powerText: String?
    let powerFraction: Double
    let isCharging: Bool
    let rangeText: String?
    let onEdit: () -> Void

    private var safeSpeed: Double { speed.isFinite ? max(speed, 0) : 0 }
    private var scaleMaximum: Double { maximum.isFinite ? max(maximum, 1) : 80 }
    private var fraction: Double { min(safeSpeed / scaleMaximum, 1) }
    private var powerTint: Color { isCharging ? .purple : .blue }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Speed", systemImage: "location.fill")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32, height: 32)
                        .background(.quaternary, in: Circle())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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

            if safeSpeed > scaleMaximum {
                Label("Above scale", systemImage: "arrow.right.to.line")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }

            if powerText != nil || rangeText != nil {
                Divider()
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) { readouts }
                    VStack(alignment: .leading, spacing: 16) { readouts }
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private var scale: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 16
            let width = max(geometry.size.width - inset * 2, 0)
            let x = inset + width * fraction

            ZStack(alignment: .topLeading) {
                // Canvas keeps all tick marks evenly spaced at any available width.
                Canvas { context, size in
                    for tick in 0...40 {
                        let major = tick.isMultiple(of: 10)
                        let medium = tick.isMultiple(of: 5)
                        let tickX = inset + width * Double(tick) / 40
                        let height: CGFloat = major ? 34 : (medium ? 25 : 15)
                        let path = Path { path in
                            path.move(to: CGPoint(x: tickX, y: 22))
                            path.addLine(to: CGPoint(x: tickX, y: 22 + height))
                        }
                        context.stroke(path,
                                       with: .color(Color.primary.opacity(major ? 0.65 : 0.22)),
                                       lineWidth: major ? 1.5 : 1)
                        if major {
                            let label = Text((scaleMaximum * Double(tick) / 40)
                                .formatted(.number.precision(.fractionLength(0))))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                            context.draw(label, at: CGPoint(x: tickX, y: size.height - 8))
                        }
                    }
                }

                Rectangle()
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: width * fraction, height: 46)
                    .offset(x: inset, y: 16)

                // A restrained accent needle follows the system tint in both appearances.
                ZStack(alignment: .top) {
                    Capsule().fill(Color.accentColor.opacity(0.18)).frame(width: 11, height: 64)
                        .blur(radius: 4)
                    Capsule().fill(Color.accentColor).frame(width: 3, height: 62)
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 9)).foregroundStyle(Color.accentColor)
                        .offset(y: -4)
                }
                .frame(width: 16, height: 64)
                .offset(x: x - 8, y: 5)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: fraction)
        }
        .frame(height: 94)
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
                .frame(height: 3)
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

#Preview("Radio • cruising") {
    RadioSpeedDial(speed: 37, unit: "km/h", maximum: 80,
                   powerText: "−840 W", powerFraction: 0.84, isCharging: false,
                   rangeText: "42 km", onEdit: {})
        .padding()
}

#Preview("Radio • charging / imperial") {
    RadioSpeedDial(speed: 18, unit: "mph", maximum: 60,
                   powerText: "240 W", powerFraction: 0.24, isCharging: true,
                   rangeText: nil, onEdit: {})
        .padding()
        .preferredColorScheme(.dark)
}
