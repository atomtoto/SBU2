//
//  ChargeActivityWidget.swift
//  ChargeActivityExtension
//

import ActivityKit
import SwiftUI
import WidgetKit

@main
struct ChargeActivityBundle: WidgetBundle {
    var body: some Widget {
        ChargeActivityWidget()
    }
}

struct ChargeActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChargeActivityAttributes.self) { context in
            ChargeLockScreenView(context: context)
                .activityBackgroundTint(Color(.secondarySystemBackground))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Charging", systemImage: "bolt.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.stateOfCharge)%")
                        .font(.title3.bold())
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 14) {
                        ProgressView(value: Double(context.state.stateOfCharge), total: 100)
                            .tint(.green)
                        RemainingTimeView(completionDate: context.state.estimatedCompletionDate,
                                          compact: false)
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Charging")
            } compactTrailing: {
                RemainingTimeView(completionDate: context.state.estimatedCompletionDate,
                                  compact: true)
            } minimal: {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Charging")
            }
            .keylineTint(.green)
        }
    }
}

private struct ChargeLockScreenView: View {
    let context: ActivityViewContext<ChargeActivityAttributes>

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label(context.attributes.deviceName, systemImage: "bolt.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Spacer()
                Text("\(context.state.stateOfCharge)%")
                    .font(.title2.bold())
                    .monospacedDigit()
            }

            ProgressView(value: Double(context.state.stateOfCharge), total: 100)
                .tint(.green)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Power")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(context.state.chargingPowerWatts) W")
                        .font(.headline)
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Full in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    RemainingTimeView(completionDate: context.state.estimatedCompletionDate,
                                      compact: false)
                        .font(.headline)
                }
            }
        }
        .padding()
        .opacity(context.isStale ? 0.65 : 1)
    }
}

private struct RemainingTimeView: View {
    let completionDate: Date?
    let compact: Bool

    var body: some View {
        if let completionDate, completionDate > .now {
            Text(timerInterval: Date.now...completionDate, countsDown: true)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityLabel("Time remaining")
        } else {
            Text(compact ? "--" : "Estimating…")
                .foregroundStyle(.secondary)
        }
    }
}
