//
//  SMLWidgetShared.swift
//  SML
//
//  Общий код между основным приложением и SMLWidget extension.
//  Читает и пишет данные через App Group UserDefaults.
//  TimelineEntry для WidgetKit.
//

import WidgetKit
import Foundation

// MARK: - App Group

private let appGroupID = "group.ca.stmaryslandscaping.app"

private var sharedDefaults: UserDefaults {
    UserDefaults(suiteName: appGroupID) ?? .standard
}

// MARK: - Keys

private enum WidgetKey {
    static let role           = "sml.widget.role"
    static let taskCount      = "sml.widget.taskCount"
    static let nextTask       = "sml.widget.nextTask"
    static let workdayStatus  = "sml.widget.workdayStatus"
    static let orderTitle     = "sml.widget.orderTitle"
    static let orderStatus    = "sml.widget.orderStatus"
    static let updatedAt      = "sml.widget.updatedAt"
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
    public let workdayStatus: String
    public let orderTitle: String
    public let orderStatus: String

    public static let placeholder = SMLWidgetEntry(
        date: Date(), role: "worker", taskCount: 3,
        nextTaskTitle: "123 Main St", workdayStatus: "active",
        orderTitle: "", orderStatus: ""
    )

    public static let guest = SMLWidgetEntry(
        date: Date(), role: "guest", taskCount: 0,
        nextTaskTitle: "", workdayStatus: "none",
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
    workdayStatus: String = "none",
    orderTitle: String = "",
    orderStatus: String = ""
) {
    let ud = sharedDefaults
    ud.set(normalizeRole(role),              forKey: WidgetKey.role)
    ud.set(taskCount,                        forKey: WidgetKey.taskCount)
    ud.set(nextTaskTitle,                    forKey: WidgetKey.nextTask)
    ud.set(normalizeWorkdayStatus(workdayStatus), forKey: WidgetKey.workdayStatus)
    ud.set(orderTitle,                       forKey: WidgetKey.orderTitle)
    ud.set(orderStatus,                      forKey: WidgetKey.orderStatus)
    ud.set(Date().timeIntervalSince1970,     forKey: WidgetKey.updatedAt)

    if #available(iOS 14.0, *) {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Read (called from widget extension)

public func smlWidgetRead() -> SMLWidgetEntry {
    let ud = sharedDefaults
    return SMLWidgetEntry(
        date:           Date(),
        role:           ud.string(forKey: WidgetKey.role)         ?? "guest",
        taskCount:      ud.integer(forKey: WidgetKey.taskCount),
        nextTaskTitle:  ud.string(forKey: WidgetKey.nextTask)     ?? "",
        workdayStatus:  ud.string(forKey: WidgetKey.workdayStatus) ?? "none",
        orderTitle:     ud.string(forKey: WidgetKey.orderTitle)   ?? "",
        orderStatus:    ud.string(forKey: WidgetKey.orderStatus)  ?? ""
    )
}
