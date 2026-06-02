//
//  SMLWidgetShared.swift
//  SML
//
//  Общий код между основным приложением и SMLWidget extension.
//  Читает и пишет данные через App Group UserDefaults.
//  TimelineEntry для WidgetKit.
//
//  ⚠️ TARGET MEMBERSHIP: этот файл должен быть в ОБОИХ таргетах:
//     - SML (основное приложение)
//     - SMLWidget (widget extension)
//  В Xcode: выбери файл -> File Inspector -> Target Membership -> поставь галочки на оба.
//

import WidgetKit
import Foundation

// MARK: - App Group

private let appGroupID = "group.ca.stmaryslandscaping.app"

// Singleton instance — created once per process.
// A computed var (old approach) created a new instance on every call; while
// UserDefaults is internally cached, a stored instance is more reliable and
// avoids edge cases where suiteName init briefly returns nil under memory pressure.
private let sharedDefaults: UserDefaults = {
    if let suite = UserDefaults(suiteName: appGroupID) {
        NSLog("[SMLWidget] App Group UserDefaults OK: %@", appGroupID)
        return suite
    }
    NSLog("[SMLWidget] WARNING: App Group '%@' not accessible - falling back to .standard. Widget will show placeholder until App Group is configured.", appGroupID)
    return .standard
}()

// MARK: - Keys

private enum WidgetKey {
    static let role           = "sml.widget.role"
    static let taskCount      = "sml.widget.taskCount"
    static let nextTask       = "sml.widget.nextTask"
    static let tasks          = "sml.widget.tasks"
    static let workdayStatus  = "sml.widget.workdayStatus"
    static let orderTitle     = "sml.widget.orderTitle"
    static let orderStatus    = "sml.widget.orderStatus"
    static let orders         = "sml.widget.orders"
    static let updatedAt      = "sml.widget.updatedAt"
}

// MARK: - Task model (workers)

public struct WidgetTask: Codable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let status: String // pending | accepted | started | completed | cancelled
}

// MARK: - Order model (clients)

public struct WidgetOrder: Codable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let status: String // pending | scheduled | in_progress | completed | cancelled
}

// MARK: - Entry

/// role values:          "guest" | "client" | "worker" | "accountant" | "manager" | "administrator" | "owner"
/// workdayStatus values: "none"  | "active" | "paused" | "ended"
/// orderStatus values:   ""      | "pending" | "scheduled" | "in_progress" | "completed" | "cancelled"
public struct SMLWidgetEntry: TimelineEntry {
    public let date: Date
    public let role: String
    public let taskCount: Int
    public let nextTaskTitle: String
    public let tasks: [WidgetTask]
    public let orders: [WidgetOrder]
    public let workdayStatus: String
    public let orderTitle: String
    public let orderStatus: String

    public static let placeholder = SMLWidgetEntry(
        date: Date(), role: "worker", taskCount: 3,
        nextTaskTitle: "123 Main St",
        tasks: [
            WidgetTask(id: "1", title: "123 Main St", status: "started"),
            WidgetTask(id: "2", title: "456 Oak Ave", status: "accepted"),
            WidgetTask(id: "3", title: "789 Pine Rd", status: "pending"),
        ],
        orders: [],
        workdayStatus: "active",
        orderTitle: "", orderStatus: ""
    )

    public static let placeholderClient = SMLWidgetEntry(
        date: Date(), role: "client", taskCount: 0,
        nextTaskTitle: "", tasks: [],
        orders: [
            WidgetOrder(id: "1", title: "Lawn Maintenance", status: "in_progress"),
            WidgetOrder(id: "2", title: "Spring Cleanup", status: "scheduled"),
        ],
        workdayStatus: "none",
        orderTitle: "Lawn Maintenance", orderStatus: "in_progress"
    )

    public static let guest = SMLWidgetEntry(
        date: Date(), role: "guest", taskCount: 0,
        nextTaskTitle: "", tasks: [], orders: [],
        workdayStatus: "none",
        orderTitle: "", orderStatus: ""
    )
}

// MARK: - Normalization

private func normalizeRole(_ raw: String) -> String {
    switch raw.lowercased() {
    case "worker":                      return "worker"
    case "accountant":                  return "accountant"
    case "manager", "menager":          return "manager"
    case "administrator", "admin":      return "administrator"
    case "owner", "boss":               return "owner"
    case "client":                      return "client"
    default:                            return "guest"
    }
}

private func normalizeWorkdayStatus(_ raw: String) -> String {
    switch raw.lowercased() {
    case "active", "open":              return "active"
    case "paused":                      return "paused"
    case "ended":                       return "ended"
    default:                            return "none"   // "not_started", "", etc.
    }
}

// MARK: - Write (called from main app)

public func smlWidgetWrite(
    role: String,
    taskCount: Int = 0,
    nextTaskTitle: String = "",
    tasks: [WidgetTask] = [],
    orders: [WidgetOrder] = [],
    workdayStatus: String = "none",
    orderTitle: String = "",
    orderStatus: String = ""
) {
    let ud = sharedDefaults
    ud.set(normalizeRole(role),                   forKey: WidgetKey.role)
    ud.set(taskCount,                             forKey: WidgetKey.taskCount)
    ud.set(nextTaskTitle,                         forKey: WidgetKey.nextTask)
    ud.set(normalizeWorkdayStatus(workdayStatus), forKey: WidgetKey.workdayStatus)
    ud.set(orderTitle,                            forKey: WidgetKey.orderTitle)
    ud.set(orderStatus,                           forKey: WidgetKey.orderStatus)
    ud.set(Date().timeIntervalSince1970,          forKey: WidgetKey.updatedAt)
    if let encoded = try? JSONEncoder().encode(tasks) {
        ud.set(encoded, forKey: WidgetKey.tasks)
    }
    if let encoded = try? JSONEncoder().encode(orders) {
        ud.set(encoded, forKey: WidgetKey.orders)
    }

    // Flush to disk before signalling WidgetKit - the widget extension
    // runs in a separate process and reads the plist directly.
    ud.synchronize()

    if #available(iOS 14.0, *) {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Read (called from widget extension)

public func smlWidgetRead() -> SMLWidgetEntry {
    let ud = sharedDefaults
    let updatedAt = ud.double(forKey: WidgetKey.updatedAt)

    // updatedAt == 0 means the main app has never written to this App Group domain.
    // This happens on first install (before the app runs) OR when the App Group
    // falls back to .standard (entitlement missing). Show placeholder so the widget
    // displays meaningful content instead of a blank/guest screen.
    if updatedAt == 0 {
        NSLog("[SMLWidget] smlWidgetRead: updatedAt=0 - App Group empty or not accessible, returning placeholder")
        return .placeholder
    }

    let tasks: [WidgetTask]
    if let data = ud.data(forKey: WidgetKey.tasks),
       let decoded = try? JSONDecoder().decode([WidgetTask].self, from: data) {
        tasks = decoded
    } else {
        NSLog("[SMLWidget] smlWidgetRead: tasks JSON decode failed or missing")
        tasks = []
    }

    let orders: [WidgetOrder]
    if let data = ud.data(forKey: WidgetKey.orders),
       let decoded = try? JSONDecoder().decode([WidgetOrder].self, from: data) {
        orders = decoded
    } else {
        orders = []
    }

    let role          = ud.string(forKey: WidgetKey.role)          ?? "guest"
    let taskCount     = ud.integer(forKey: WidgetKey.taskCount)
    let workdayStatus = ud.string(forKey: WidgetKey.workdayStatus) ?? "none"

    NSLog("[SMLWidget] smlWidgetRead: role=%@ tasks=%d workday=%@ updatedAt=%.0f",
          role, taskCount, workdayStatus, updatedAt)

    return SMLWidgetEntry(
        date:           Date(),
        role:           role,
        taskCount:      taskCount,
        nextTaskTitle:  ud.string(forKey: WidgetKey.nextTask)  ?? "",
        tasks:          tasks,
        orders:         orders,
        workdayStatus:  workdayStatus,
        orderTitle:     ud.string(forKey: WidgetKey.orderTitle)  ?? "",
        orderStatus:    ud.string(forKey: WidgetKey.orderStatus) ?? ""
    )
}
