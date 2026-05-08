//
//  SMLWidgetShared.swift
//  SML
//
//  Назначение:
//  - Общий код между основным приложением и SMLWidget extension.
//  - Читает и пишет данные через App Group UserDefaults.
//  - TimelineEntry для WidgetKit.
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
    static let updatedAt      = "sml.widget.updatedAt"
}

// MARK: - Entry

/// workdayStatus values: "none" | "active" | "paused" | "ended"
public struct SMLWidgetEntry: TimelineEntry {
    public let date: Date
    public let role: String
    public let taskCount: Int
    public let nextTaskTitle: String
    public let workdayStatus: String

    public static let placeholder = SMLWidgetEntry(
        date: Date(),
        role: "worker",
        taskCount: 3,
        nextTaskTitle: "123 Main St",
        workdayStatus: "active"
    )

    public static let guest = SMLWidgetEntry(
        date: Date(),
        role: "guest",
        taskCount: 0,
        nextTaskTitle: "",
        workdayStatus: "none"
    )
}

// MARK: - Write (called from main app)

public func smlWidgetWrite(role: String, taskCount: Int, nextTaskTitle: String, workdayStatus: String = "none") {
    let ud = sharedDefaults
    ud.set(role,            forKey: WidgetKey.role)
    ud.set(taskCount,       forKey: WidgetKey.taskCount)
    ud.set(nextTaskTitle,   forKey: WidgetKey.nextTask)
    ud.set(workdayStatus,   forKey: WidgetKey.workdayStatus)
    ud.set(Date().timeIntervalSince1970, forKey: WidgetKey.updatedAt)

    if #available(iOS 14.0, *) {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Read (called from widget extension)

public func smlWidgetRead() -> SMLWidgetEntry {
    let ud = sharedDefaults
    let role           = ud.string(forKey: WidgetKey.role)          ?? "guest"
    let taskCount      = ud.integer(forKey: WidgetKey.taskCount)
    let nextTask       = ud.string(forKey: WidgetKey.nextTask)       ?? ""
    let workdayStatus  = ud.string(forKey: WidgetKey.workdayStatus)  ?? "none"
    return SMLWidgetEntry(date: Date(), role: role, taskCount: taskCount, nextTaskTitle: nextTask, workdayStatus: workdayStatus)
}
