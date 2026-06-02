//
//  SMLWidget.swift
//  SMLWidget
//
//  Адаптивный виджет: разный контент для гостей, клиентов, рабочих и менеджеров.
//  Размеры: small, medium, large.
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
        // 5-minute refresh so stale App Group data is replaced quickly after the app
        // returns to foreground and writes fresh data.
        let next  = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Brand tokens

private let brandGreen = Color(red: 67/255.0, green: 130/255.0, blue: 57/255.0)
private let warmBg     = Color(red: 243/255.0, green: 240/255.0, blue: 232/255.0)
private let warmSurf   = Color(red: 247/255.0, green: 243/255.0, blue: 234/255.0)
private let ink        = Color(red: 18/255.0,  green: 22/255.0,  blue: 18/255.0)

// MARK: - containerBackground helper

private extension View {
    @ViewBuilder
    func smlBg() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(.background, for: .widget)
        } else {
            self
        }
    }
}

// MARK: - Role helpers

private let staffRoles: Set<String> = ["worker", "accountant", "manager", "administrator", "owner"]

private func isStaff(_ role: String) -> Bool { staffRoles.contains(role) }

// MARK: - Tab descriptor

private struct WTab: Identifiable {
    let icon: String
    let label: String
    let url: URL
    var id: String { url.absoluteString }
}

// Safe URL builder - sml:// scheme strings are compile-time constants and never fail,
// but using a helper avoids force-unwraps scattered across the file.
private func smlURL(_ path: String) -> URL {
    URL(string: "sml://\(path)") ?? URL(string: "sml://home")!
}

private func tabs(for role: String) -> [WTab] {
    switch role {
    case "worker":
        return [
            .init(icon: "house.fill",               label: "Home",      url: smlURL("home")),
            .init(icon: "calendar",                 label: "Workday",   url: smlURL("workday")),
            .init(icon: "checklist",                label: "Tasks",     url: smlURL("tasks-today")),
            .init(icon: "exclamationmark.bubble",   label: "Report",    url: smlURL("report")),
        ]
    case "accountant":
        return [
            .init(icon: "house.fill",               label: "Home",      url: smlURL("home")),
            .init(icon: "calendar.badge.clock",     label: "Billing",   url: smlURL("billing")),
            .init(icon: "calendar",                 label: "Workday",   url: smlURL("workday")),
            .init(icon: "dollarsign.square",        label: "Payroll",   url: smlURL("payroll")),
        ]
    case "manager":
        return [
            .init(icon: "house.fill",               label: "Home",      url: smlURL("home")),
            .init(icon: "plus.square.fill",         label: "Create",    url: smlURL("create")),
            .init(icon: "calendar",                 label: "Workday",   url: smlURL("workday")),
            .init(icon: "tray.full",                label: "Tasks",     url: smlURL("all-tasks")),
        ]
    case "administrator":
        return [
            .init(icon: "house.fill",               label: "Home",      url: smlURL("home")),
            .init(icon: "plus.square.fill",         label: "Create",    url: smlURL("create")),
            .init(icon: "rectangle.3.group.fill",   label: "Workspace", url: smlURL("workspace")),
            .init(icon: "tray.full",                label: "All Tasks", url: smlURL("all-tasks")),
        ]
    case "owner":
        return [
            .init(icon: "house.fill",               label: "Home",      url: smlURL("home")),
            .init(icon: "plus.square.fill",         label: "Create",    url: smlURL("create")),
            .init(icon: "calendar",                 label: "Workday",   url: smlURL("workday")),
            .init(icon: "tray.full",                label: "All Tasks", url: smlURL("all-tasks")),
        ]
    case "client":
        return [
            .init(icon: "house.fill",                    label: "Home",        url: smlURL("home")),
            .init(icon: "list.bullet.clipboard.fill",    label: "Requests",    url: smlURL("requests")),
            .init(icon: "paperplane.fill",               label: "New Request", url: smlURL("quote")),
            .init(icon: "person.crop.circle.fill",       label: "Account",     url: smlURL("account")),
        ]
    default: // guest
        return [
            .init(icon: "paperplane.fill",          label: "Get Quote", url: smlURL("quote")),
            .init(icon: "leaf.fill",                label: "Services",  url: smlURL("services")),
            .init(icon: "house.fill",               label: "Home",      url: smlURL("home")),
            .init(icon: "person.fill",              label: "Sign In",   url: smlURL("account")),
        ]
    }
}

// MARK: - Order row (used in client medium/large widgets)

private struct OrderRow: View {
    let order: WidgetOrder

    // in_progress = green fill (being worked on right now)
    // scheduled   = orange fill (date is set)
    // pending     = gray hollow (submitted, waiting)
    private var dotColor: Color {
        switch order.status {
        case "in_progress": return brandGreen
        case "scheduled":   return .orange
        default:            return Color.primary.opacity(0.25)
        }
    }

    private var icon: String {
        switch order.status {
        case "in_progress", "scheduled": return "circle.fill"
        default:                         return "circle"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(dotColor)
                .frame(width: 10)
            Text(order.title)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}

// MARK: - Task row (used in worker medium/large widgets)

private struct TaskRow: View {
    let task: WidgetTask

    // started = green fill (in progress)
    // accepted = orange fill (accepted, not yet started)
    // pending / assigned / anything else = gray hollow (new, not yet accepted)
    private var dotColor: Color {
        switch task.status {
        case "started":  return brandGreen
        case "accepted": return .orange
        default:         return Color.primary.opacity(0.25)
        }
    }

    private var icon: String {
        switch task.status {
        case "started", "accepted": return "circle.fill"
        default:                    return "circle"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(dotColor)
                .frame(width: 10)
            Text(task.title)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}

// MARK: - Workday badge

private struct WorkdayBadge: View {
    let status: String

    private var dotColor: Color {
        switch status {
        case "active": return .green
        case "paused": return .orange
        case "ended":  return .gray
        default:       return Color.primary.opacity(0.25)
        }
    }

    private var text: String {
        switch status {
        case "active": return "Working"
        case "paused": return "On Break"
        case "ended":  return "Day Ended"
        default:       return "Not Started"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(dotColor).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Order progress (4 steps)

private struct OrderProgress: View {
    let status: String // pending | scheduled | in_progress | completed | cancelled

    // -1 = cancelled (all circles hollow/gray, none highlighted)
    private var step: Int {
        switch status {
        case "pending":     return 0
        case "scheduled":   return 1
        case "in_progress": return 2
        case "completed":   return 3
        case "cancelled":   return -1
        default:            return 0
        }
    }

    private let labels = ["Submitted", "Scheduled", "In Progress", "Done"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { i in
                VStack(spacing: 3) {
                    Circle()
                        .fill(i <= step ? brandGreen : Color.primary.opacity(0.15))
                        .frame(width: 8, height: 8)
                    Text(labels[i])
                        .font(.system(size: 8, weight: i == step ? .semibold : .regular))
                        .foregroundStyle(i == step ? brandGreen : Color.primary.opacity(0.40))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                if i < 3 {
                    Rectangle()
                        .fill(i < step ? brandGreen : Color.primary.opacity(0.15))
                        .frame(height: 1.5)
                        .offset(y: -6)
                }
            }
        }
    }
}

// MARK: - Tab bar row

private struct WidgetTabBar: View {
    let items: [WTab]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { tab in
                Link(destination: tab.url) {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(brandGreen)
                        Text(tab.label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Primary tap URL

private func primaryURL(for role: String) -> URL {
    switch role {
    case "guest":   return smlURL("quote")
    case "client":  return smlURL("requests")
    case "worker":  return smlURL("tasks-today")
    default:        return smlURL("workday")
    }
}

// MARK: - Small widget

struct SMLSmallWidgetView: View {
    let e: SMLWidgetEntry

    var body: some View {
        Link(destination: primaryURL(for: e.role)) {
            VStack(alignment: .leading, spacing: 0) {

                Image("SMLLeaf")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)

                Spacer()

                if e.role == "client" {
                    clientBody
                } else if e.role == "worker" {
                    workerBody
                } else if isStaff(e.role) {
                    staffBody
                } else {
                    guestBody
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .smlBg()
        .widgetURL(primaryURL(for: e.role))
    }

    // Client: most important active order (small widget)
    private var clientBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let top = e.orders.first {
                Text(e.orders.count == 1 ? "Active Request" : "\(e.orders.count) Active Requests")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(brandGreen)
                    .tracking(0.5)
                Text(top.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                OrderProgress(status: top.status)
                    .padding(.top, 4)
            } else {
                Text("My\nRequests")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineSpacing(1)
                Text("Tap to view all")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    // Worker: workday status + task count
    private var workerBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            WorkdayBadge(status: e.workdayStatus)
            Text("\(e.taskCount)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(brandGreen)
                .lineLimit(1)
            Text(e.taskCount == 1 ? "task today" : "tasks today")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // Other staff: workday + role
    private var staffBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            WorkdayBadge(status: e.workdayStatus)
            Text(staffRoleLabel(e.role))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("Tap to open account")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // Guest
    private var guestBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Free\nEstimate")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(brandGreen)
                .lineSpacing(1)
            Text("Tap to request")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Medium widget

struct SMLMediumWidgetView: View {
    let e: SMLWidgetEntry
    private var tabList: [WTab] { tabs(for: e.role) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 14)
                .padding(.top, 12)

            middleContent
                .padding(.horizontal, 14)
                .padding(.top, 8)

            Spacer(minLength: 4)

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
                .padding(.horizontal, 10)

            WidgetTabBar(items: tabList)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
        }
        .smlBg()
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 10) {
            Image("SMLLeaf")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
            Text("St. Marys Landscaping")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            if isStaff(e.role) {
                Link(destination: smlURL("workday")) {
                    WorkdayBadge(status: e.workdayStatus)
                }
            } else if e.role == "client" {
                Text("My Account")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Text("Since 1971")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var middleContent: some View {
        if e.role == "client" {
            clientMiddle
        } else if e.role == "worker" || (isStaff(e.role) && !e.tasks.isEmpty) {
            workerMiddle
        } else if isStaff(e.role) {
            staffMiddle
        } else {
            guestMiddle
        }
    }

    // Client: list of active orders
    private var clientMiddle: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                if e.orders.isEmpty {
                    Text("No active requests")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Tap New Request below to submit one")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(e.orders.prefix(3)) { order in
                        OrderRow(order: order)
                    }
                    if e.orders.count > 3 {
                        Text("+ \(e.orders.count - 3) more")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
        }
    }

    // Worker: task count + task list (up to 5)
    private var workerMiddle: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Link(destination: smlURL("workday")) {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(e.taskCount)")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(brandGreen)
                        Text(e.taskCount == 1 ? "task today" : "tasks today")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(e.tasks.prefix(5)) { task in
                    Link(destination: smlURL("tasks-today")) {
                        TaskRow(task: task)
                    }
                }
                if e.tasks.count > 5 {
                    Text("+ \(e.tasks.count - 5) more")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                } else if e.tasks.isEmpty && !e.nextTaskTitle.isEmpty {
                    Text("Next: \(e.nextTaskTitle)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }

    // Staff (manager, accountant, owner, administrator)
    private var staffMiddle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(staffRoleLabel(e.role))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Use tabs below for quick access")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // Guest
    private var guestMiddle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Get a Free Estimate")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(brandGreen)
                Text("Landscape Design · Build · Care")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Large widget

struct SMLLargeWidgetView: View {
    let e: SMLWidgetEntry
    private var tabList: [WTab] { tabs(for: e.role) }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image("SMLLeaf")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("St. Marys Landscaping")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(isStaff(e.role) ? staffRoleLabel(e.role) : (e.role == "client" ? "Client Account" : "Landscaping Services"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isStaff(e.role) {
                    Link(destination: smlURL("workday")) {
                        WorkdayBadge(status: e.workdayStatus)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 0.5)
                .padding(.horizontal, 14)
                .padding(.top, 10)

            // Main body
            largeBody
                .padding(.horizontal, 16)
                .padding(.top, 12)

            Spacer(minLength: 8)

            // Quick links grid 2x2
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(tabList) { tab in
                    Link(destination: tab.url) {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(brandGreen)
                                .frame(width: 20)
                            Text(tab.label)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .smlBg()
    }

    @ViewBuilder
    private var largeBody: some View {
        if e.role == "client" {
            clientLarge
        } else if e.role == "worker" || (isStaff(e.role) && !e.tasks.isEmpty) {
            workerLarge
        } else if isStaff(e.role) {
            staffLarge
        } else {
            guestLarge
        }
    }

    private var clientLarge: some View {
        VStack(alignment: .leading, spacing: 6) {
            if e.orders.isEmpty {
                Text("No active requests")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Submit a service or material request and track it in real time.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            } else {
                Text(e.orders.count == 1 ? "1 Active Request" : "\(e.orders.count) Active Requests")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(brandGreen)
                    .tracking(0.8)
                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(height: 0.5)
                    .padding(.vertical, 2)
                ForEach(e.orders.prefix(6)) { order in
                    OrderRow(order: order)
                }
                if e.orders.count > 6 {
                    Text("+ \(e.orders.count - 6) more")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var workerLarge: some View {
        VStack(alignment: .leading, spacing: 6) {
            Link(destination: smlURL("workday")) {
                WorkdayBadge(status: e.workdayStatus)
            }
            Link(destination: smlURL("workday")) {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(e.taskCount)")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(brandGreen)
                    Text(e.taskCount == 1 ? "task today" : "tasks today")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            if !e.tasks.isEmpty {
                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(height: 0.5)
                    .padding(.vertical, 2)
                ForEach(e.tasks) { task in
                    Link(destination: smlURL("tasks-today")) {
                        TaskRow(task: task)
                    }
                }
            } else if !e.nextTaskTitle.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(brandGreen)
                    Text(e.nextTaskTitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var staffLarge: some View {
        VStack(alignment: .leading, spacing: 6) {
            WorkdayBadge(status: e.workdayStatus)
            Text(staffRoleLabel(e.role))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
            Text("Use the quick links below to navigate.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var guestLarge: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Get a\nFree Estimate")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(brandGreen)
                .lineSpacing(2)
            Text("Professional landscaping for St. Marys & surrounding areas. Since 1971.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
    }
}

// MARK: - Role label helper

private func staffRoleLabel(_ role: String) -> String {
    switch role {
    case "worker":         return "Worker"
    case "accountant":     return "Accountant"
    case "manager":        return "Manager"
    case "administrator":  return "Administrator"
    case "owner":          return "Owner"
    default:               return "Staff"
    }
}

// MARK: - Entry view dispatcher

struct SMLWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: SMLWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:  SMLSmallWidgetView(e: entry)
        case .systemMedium: SMLMediumWidgetView(e: entry)
        case .systemLarge:  SMLLargeWidgetView(e: entry)
        default:            SMLSmallWidgetView(e: entry)
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
        .description("Quick access to your workday, tasks and requests.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
