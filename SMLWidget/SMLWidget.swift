//
//  SMLWidget.swift
//  SMLWidget
//
//  Дизайн:
//  - Цвет фона задаёт система (белый/тёмный по настройке телефона).
//  - Верхняя часть: логотип + статус рабочего дня (для staff).
//  - Нижняя часть: 4 иконки вкладок, как в приложении, по роли.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline provider

struct SMLWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SMLWidgetEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (SMLWidgetEntry) -> Void) {
        completion(context.isPreview ? .placeholder : smlWidgetRead())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SMLWidgetEntry>) -> Void) {
        let entry = smlWidgetRead()
        let next  = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Brand color (used only for accents, not background)

private let brandGreen = Color(red: 67 / 255.0, green: 130 / 255.0, blue: 57 / 255.0)

// MARK: - iOS 16/17 containerBackground (system colour — no override)

private extension View {
    @ViewBuilder
    func smlSystemBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(.background, for: .widget)
        } else {
            self
        }
    }
}

// MARK: - Tab descriptor

private struct WidgetTab {
    let icon: String
    let label: String
    let url: URL
}

private func tabs(for role: String) -> [WidgetTab] {
    switch role {
    case "worker":
        return [
            .init(icon: "house",            label: "Home",     url: URL(string: "sml://home")!),
            .init(icon: "calendar",         label: "Workday",  url: URL(string: "sml://workday")!),
            .init(icon: "checklist",        label: "Tasks",    url: URL(string: "sml://tasks-today")!),
            .init(icon: "exclamationmark.bubble", label: "Report", url: URL(string: "sml://report")!),
        ]
    case "accountant":
        return [
            .init(icon: "house",            label: "Home",     url: URL(string: "sml://home")!),
            .init(icon: "calendar.badge.clock", label: "Billing", url: URL(string: "sml://billing")!),
            .init(icon: "briefcase",        label: "Workday",  url: URL(string: "sml://workday")!),
            .init(icon: "dollarsign.square", label: "Payroll", url: URL(string: "sml://payroll")!),
        ]
    case "admin":
        return [
            .init(icon: "house",            label: "Home",     url: URL(string: "sml://home")!),
            .init(icon: "plus.square",      label: "Create",   url: URL(string: "sml://create")!),
            .init(icon: "rectangle.3.group", label: "Workspace", url: URL(string: "sml://workspace")!),
            .init(icon: "tray.full",        label: "All Tasks", url: URL(string: "sml://all-tasks")!),
        ]
    case "owner":
        return [
            .init(icon: "person.crop.circle", label: "Account", url: URL(string: "sml://account")!),
            .init(icon: "plus.square",      label: "Create",   url: URL(string: "sml://create")!),
            .init(icon: "briefcase",        label: "Workday",  url: URL(string: "sml://workday")!),
            .init(icon: "tray.full",        label: "All Tasks", url: URL(string: "sml://all-tasks")!),
        ]
    case "menager":
        return [
            .init(icon: "house",            label: "Home",     url: URL(string: "sml://home")!),
            .init(icon: "plus.square",      label: "Create",   url: URL(string: "sml://create")!),
            .init(icon: "briefcase",        label: "Workday",  url: URL(string: "sml://workday")!),
            .init(icon: "tray.full",        label: "All Tasks", url: URL(string: "sml://all-tasks")!),
        ]
    case "client":
        return [
            .init(icon: "house",            label: "Home",     url: URL(string: "sml://home")!),
            .init(icon: "list.bullet.clipboard", label: "Requests", url: URL(string: "sml://requests")!),
            .init(icon: "paperplane",       label: "New Request", url: URL(string: "sml://quote")!),
            .init(icon: "person.crop.circle", label: "Account", url: URL(string: "sml://account")!),
        ]
    default: // guest
        return [
            .init(icon: "house",            label: "Home",     url: URL(string: "sml://home")!),
            .init(icon: "person",           label: "Sign In",  url: URL(string: "sml://account")!),
            .init(icon: "paperplane",       label: "Get Quote", url: URL(string: "sml://quote")!),
            .init(icon: "leaf",             label: "Services", url: URL(string: "sml://services")!),
        ]
    }
}

// MARK: - Workday status badge

private struct WorkdayBadge: View {
    let status: String  // "none" | "active" | "paused" | "ended"

    private var dot: Color {
        switch status {
        case "active": return .green
        case "paused": return .orange
        case "ended":  return .gray
        default:       return .red
        }
    }

    private var label: String {
        switch status {
        case "active": return "Working"
        case "paused": return "On Break"
        case "ended":  return "Day Ended"
        default:       return "Not Started"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dot)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Tab bar row (bottom of medium widget)

private struct WidgetTabBar: View {
    let tabs: [WidgetTab]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.label) { tab in
                Link(destination: tab.url) {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(brandGreen)
                        Text(tab.label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Staff status content

private let staffRoles: Set<String> = ["worker", "accountant", "owner", "menager", "admin"]

private func isStaff(_ role: String) -> Bool { staffRoles.contains(role) }

// MARK: - Small widget

struct SMLSmallWidgetView: View {
    let entry: SMLWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Logo
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 22)

            Spacer()

            if isStaff(entry.role) {
                WorkdayBadge(status: entry.workdayStatus)

                if entry.role == "worker" && entry.taskCount > 0 {
                    Text("\(entry.taskCount) task\(entry.taskCount == 1 ? "" : "s") today")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else if entry.role == "client" {
                Text("My Requests")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Tap to view")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text("St. Marys\nLandscaping")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Tap to open")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .smlSystemBackground()
        .widgetURL(tabs(for: entry.role).first?.url ?? URL(string: "sml://home")!)
    }
}

// MARK: - Medium widget

struct SMLMediumWidgetView: View {
    let entry: SMLWidgetEntry
    private var tabList: [WidgetTab] { tabs(for: entry.role) }

    var body: some View {
        VStack(spacing: 0) {

            // Top: logo + status / info
            HStack(alignment: .top, spacing: 10) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 26)

                Spacer()

                if isStaff(entry.role) {
                    WorkdayBadge(status: entry.workdayStatus)
                } else if entry.role == "client" {
                    Text("Client")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Sign in to get started")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            // Middle: role info
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if entry.role == "worker" {
                        Text("\(entry.taskCount)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(brandGreen)
                        Text(entry.taskCount == 1 ? "task today" : "tasks today")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        if !entry.nextTaskTitle.isEmpty {
                            Text(entry.nextTaskTitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else if isStaff(entry.role) {
                        Text("St. Marys Landscaping")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(roleName(entry.role))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else if entry.role == "client" {
                        Text("Welcome back")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("View your requests below")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Professional landscaping")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Get a free quote today")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            Spacer()

            // Divider
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
                .padding(.horizontal, 10)

            // Bottom: tab bar
            WidgetTabBar(tabs: tabList)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
        }
        .smlSystemBackground()
    }
}

private func roleName(_ role: String) -> String {
    switch role {
    case "accountant": return "Accountant"
    case "admin":      return "Administrator"
    case "owner":      return "Owner"
    case "menager":    return "Manager"
    default:           return ""
    }
}

// MARK: - Entry view

struct SMLWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: SMLWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:  SMLSmallWidgetView(entry: entry)
        case .systemMedium: SMLMediumWidgetView(entry: entry)
        default:            SMLSmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Widget definition

struct SMLWidget: Widget {
    let kind = "SMLWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SMLWidgetProvider()) { entry in
            SMLWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("St. Marys Landscaping")
        .description("Quick access to your workday and tasks.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
