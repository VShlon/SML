//
//  SMLIntents.swift
//  SML
//
//  Siri Shortcuts via App Intents.
//  Workers: Start Workday, End Workday, View Tasks.
//  Clients: New Request, View My Requests.
//

import AppIntents
import Foundation

// MARK: - Routing key

private let siriRouteKey = "sml.siri.route"

// MARK: - Worker: Start Workday

struct StartWorkdayIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Workday"
    static var description = IntentDescription("Open St. Marys Landscaping and go to your workday screen.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set("workday", forKey: siriRouteKey)
        return .result()
    }
}

// MARK: - Worker: End Workday

struct EndWorkdayIntent: AppIntent {
    static var title: LocalizedStringResource = "End Workday"
    static var description = IntentDescription("Open St. Marys Landscaping and go to your workday screen to end the day.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set("workday", forKey: siriRouteKey)
        return .result()
    }
}

// MARK: - Worker: View Today's Tasks

struct ViewTasksIntent: AppIntent {
    static var title: LocalizedStringResource = "View Today's Tasks"
    static var description = IntentDescription("Open St. Marys Landscaping and see your tasks for today.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set("tasks", forKey: siriRouteKey)
        return .result()
    }
}

// MARK: - Client: New Service Request

struct NewRequestIntent: AppIntent {
    static var title: LocalizedStringResource = "New Service Request"
    static var description = IntentDescription("Open St. Marys Landscaping to submit a new service or material request.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set("new-request", forKey: siriRouteKey)
        return .result()
    }
}

// MARK: - Client: View My Requests

struct ViewRequestsIntent: AppIntent {
    static var title: LocalizedStringResource = "View My Requests"
    static var description = IntentDescription("Open St. Marys Landscaping and see all your service requests.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set("requests", forKey: siriRouteKey)
        return .result()
    }
}

// MARK: - App Shortcuts (appear in Siri automatically)

@available(iOS 16.4, *)
struct SMLShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartWorkdayIntent(),
            phrases: [
                "Start workday in \(.applicationName)",
                "Begin my workday \(.applicationName)",
                "Clock in \(.applicationName)"
            ],
            shortTitle: "Start Workday",
            systemImageName: "clock.badge.checkmark"
        )
        AppShortcut(
            intent: EndWorkdayIntent(),
            phrases: [
                "End workday in \(.applicationName)",
                "Finish my workday \(.applicationName)",
                "Clock out \(.applicationName)"
            ],
            shortTitle: "End Workday",
            systemImageName: "clock.badge.xmark"
        )
        AppShortcut(
            intent: ViewTasksIntent(),
            phrases: [
                "Show my tasks in \(.applicationName)",
                "What are my tasks \(.applicationName)"
            ],
            shortTitle: "Today's Tasks",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: NewRequestIntent(),
            phrases: [
                "New landscaping request \(.applicationName)",
                "Request a service \(.applicationName)",
                "Order landscaping \(.applicationName)"
            ],
            shortTitle: "New Request",
            systemImageName: "paperplane"
        )
        AppShortcut(
            intent: ViewRequestsIntent(),
            phrases: [
                "My requests in \(.applicationName)",
                "Show my orders \(.applicationName)"
            ],
            shortTitle: "My Requests",
            systemImageName: "list.bullet.clipboard"
        )
    }
}

// MARK: - Siri route consumed by ContentView / iPadRootView

extension UserDefaults {
    static let siriRouteKey = "sml.siri.route"

    func consumeSiriRoute() -> String? {
        let val = string(forKey: Self.siriRouteKey)
        if val != nil { removeObject(forKey: Self.siriRouteKey) }
        return val
    }
}
