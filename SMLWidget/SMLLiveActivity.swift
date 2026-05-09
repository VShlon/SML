//
//  SMLLiveActivity.swift
//  SMLWidget
//
//  Live Activity views for:
//  - WorkdayLiveActivity  (workers: lock screen timer + Dynamic Island)
//  - OrderLiveActivity    (clients: order progress bar + Dynamic Island)
//

import ActivityKit
import WidgetKit
import SwiftUI

private let brandGreen = Color(red: 67/255.0, green: 130/255.0, blue: 57/255.0)

// MARK: - Workday Live Activity

@available(iOS 16.2, *)
struct WorkdayLockScreenView: View {
    let context: ActivityViewContext<WorkdayActivityAttributes>

    private var dot: Color {
        switch context.state.status {
        case "active": return .green
        case "paused": return .orange
        default:       return .gray
        }
    }

    private var statusLabel: String {
        switch context.state.status {
        case "active": return "Working"
        case "paused": return "On Break"
        case "ended":  return "Day Ended"
        default:       return "Workday"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Logo
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(dot).frame(width: 8, height: 8)
                    Text(statusLabel)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(context.state.workerName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if context.state.status == "ended" {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else if context.state.status == "paused" {
                // Break timer: counts up from when this pause started
                Text(context.state.pauseStart, style: .timer)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
                    .monospacedDigit()
            } else {
                // Work timer: counts up actual working time (pauses excluded)
                Text(context.state.adjustedStart, style: .timer)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(brandGreen)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

@available(iOS 16.2, *)
struct WorkdayLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkdayActivityAttributes.self) { context in
            WorkdayLockScreenView(context: context)
                .background(Color(UIColor.systemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded (long press)
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(context.state.status == "active" ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.state.status == "active" ? "Working" : "On Break")
                                .font(.system(size: 13, weight: .semibold))
                            Text(context.state.workerName)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.status == "paused" {
                        Text(context.state.pauseStart, style: .timer)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)
                            .monospacedDigit()
                    } else if context.state.status != "ended" {
                        Text(context.state.adjustedStart, style: .timer)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(brandGreen)
                            .monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("St. Marys Landscaping")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Circle()
                    .fill(context.state.status == "active" ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
            } compactTrailing: {
                if context.state.status == "paused" {
                    Text(context.state.pauseStart, style: .timer)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                        .frame(maxWidth: 52)
                } else {
                    Text(context.state.adjustedStart, style: .timer)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(brandGreen)
                        .monospacedDigit()
                        .frame(maxWidth: 52)
                }
            } minimal: {
                Circle()
                    .fill(context.state.status == "active" ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
            }
        }
    }
}

// MARK: - Order Status Live Activity

private let orderStages = ["Submitted", "Scheduled", "In Progress", "Completed"]

// Maps both server-side ("pending") and legacy ("submitted") values
private func stageIndex(for status: String) -> Int {
    switch status {
    case "pending", "submitted":    return 0
    case "scheduled":               return 1
    case "in_progress":             return 2
    case "completed":               return 3
    default:                        return 0
    }
}

@available(iOS 16.2, *)
struct OrderLockScreenView: View {
    let context: ActivityViewContext<OrderActivityAttributes>

    private var idx: Int { stageIndex(for: context.state.status) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 18)
                Spacer()
                Text(context.state.serviceName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }

            // Progress track
            HStack(spacing: 0) {
                ForEach(orderStages.indices, id: \.self) { i in
                    Circle()
                        .fill(i <= idx ? brandGreen : Color(UIColor.systemGray4))
                        .frame(width: 10, height: 10)
                    if i < orderStages.count - 1 {
                        Rectangle()
                            .fill(i < idx ? brandGreen : Color(UIColor.systemGray4))
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            Text(orderStages[idx])
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(brandGreen)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(UIColor.systemBackground))
    }
}

@available(iOS 16.2, *)
struct OrderLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OrderActivityAttributes.self) { context in
            OrderLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.serviceName)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text("Order #\(context.attributes.orderId)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(orderStages[stageIndex(for: context.state.status)])
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(brandGreen)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // Mini progress bar in expanded island
                    HStack(spacing: 0) {
                        ForEach(orderStages.indices, id: \.self) { i in
                            let filled = i <= stageIndex(for: context.state.status)
                            Capsule()
                                .fill(filled ? brandGreen : Color(UIColor.systemGray5))
                                .frame(height: 4)
                            if i < orderStages.count - 1 {
                                Spacer().frame(width: 4)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(brandGreen)
            } compactTrailing: {
                Text(orderStages[stageIndex(for: context.state.status)])
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(brandGreen)
                    .lineLimit(1)
                    .frame(maxWidth: 70)
            } minimal: {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(brandGreen)
            }
        }
    }
}
