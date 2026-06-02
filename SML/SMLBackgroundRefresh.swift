//
//  SMLBackgroundRefresh.swift
//  SML
//
//  Background App Refresh handler.
//  Fetches live-status from the server in the background (no open app required)
//  and writes the result to the App Group so the widget shows current data.
//
//  SETUP REQUIRED IN XCODE (one-time, cannot be done from code):
//    1. Select the SML target -> Signing & Capabilities
//    2. Add "Background Modes" capability -> check "Background fetch"
//    3. The Info.plist entries below handle the BGTaskScheduler identifier.
//
//  Auth: uses cookies stored in HTTPCookieStorage.shared, which WebView.swift
//  copies there on every page load via syncCookiesToSharedStorage().
//  These cookies persist to disk and are available during background tasks.
//

import BackgroundTasks
import WidgetKit
import Foundation

enum SMLBackgroundRefresh {

    static let taskId        = "ca.stmaryslandscaping.app.widget-refresh"
    static let minIntervalS  = 15.0 * 60   // iOS will not fire sooner than this

    private static let liveStatusURL = URL(string: "https://stmaryslandscaping.ca/wp-json/sml/v1/live-status")!

    // MARK: - Registration (call once in AppDelegate.application(_:didFinishLaunchingWithOptions:))

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleTask(refreshTask)
        }
    }

    // MARK: - Scheduling

    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minIntervalS)
        do {
            try BGTaskScheduler.shared.submit(request)
            NSLog("[BGRefresh] next refresh scheduled (earliest: %0.0f min)", minIntervalS / 60)
        } catch {
            NSLog("[BGRefresh] schedule failed: %@", "\(error)")
        }
    }

    // MARK: - Fetch and write (shared logic)

    // Fetches live-status from the server and writes the result to the App Group.
    // Called from the BGAppRefreshTask handler, foreground return, and silent push.
    // completion(true) = data written; completion(false) = skipped (auth/network error).
    static func fetchAndWrite(completion: ((Bool) -> Void)? = nil) {
        var req = URLRequest(
            url: liveStatusURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 20
        )

        // Attach WordPress session cookies so the request is authenticated.
        if let cookies = HTTPCookieStorage.shared.cookies(for: liveStatusURL), !cookies.isEmpty {
            for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) {
                req.setValue(value, forHTTPHeaderField: field)
            }
        }

        URLSession.shared.dataTask(with: req) { data, response, error in
            // Network error - leave App Group untouched.
            guard let data, error == nil else {
                NSLog("[BGRefresh] network error: %@", error?.localizedDescription ?? "nil")
                completion?(false)
                return
            }

            // Non-200 (redirect to login, 401, 5xx) - leave App Group untouched.
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                NSLog("[BGRefresh] HTTP %d - skipping App Group write", http.statusCode)
                completion?(false)
                return
            }

            // authenticated:false means session is expired - do not wipe widget data.
            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                (json["authenticated"] as? Bool) == true
            else {
                NSLog("[BGRefresh] not authenticated or bad JSON - skipping App Group write")
                completion?(false)
                return
            }

            let role          = (json["role"]           as? String) ?? "guest"
            let workdayStatus = (json["workday_status"] as? String) ?? "not_started"
            let taskCount     = (json["task_count"]     as? Int)    ?? 0
            let nextTask      = (json["next_task"]      as? String) ?? ""
            let orderTitle    = (json["order_title"]    as? String) ?? ""
            let orderStatus   = (json["order_status"]   as? String) ?? ""

            var widgetTasks: [WidgetTask] = []
            if let raw = json["tasks"] as? [[String: Any]] {
                widgetTasks = raw.enumerated().map { i, t in
                    WidgetTask(
                        id:     (t["id"]     as? String) ?? "\(i)",
                        title:  (t["title"]  as? String) ?? "",
                        status: (t["status"] as? String) ?? "pending"
                    )
                }
            }

            var widgetOrders: [WidgetOrder] = []
            if let raw = json["orders"] as? [[String: Any]] {
                widgetOrders = raw.enumerated().map { i, o in
                    WidgetOrder(
                        id:     (o["id"]     as? String) ?? "\(i)",
                        title:  (o["title"]  as? String) ?? "",
                        status: (o["status"] as? String) ?? "pending"
                    )
                }
            }

            smlWidgetWrite(
                role:          role,
                taskCount:     taskCount,
                nextTaskTitle: nextTask,
                tasks:         widgetTasks,
                orders:        widgetOrders,
                workdayStatus: workdayStatus,
                orderTitle:    orderTitle,
                orderStatus:   orderStatus
            )

            NSLog("[BGRefresh] widget updated: role=%@ tasks=%d status=%@", role, taskCount, workdayStatus)
            completion?(true)
        }.resume()
    }

    // MARK: - Task handler

    private static func handleTask(_ task: BGAppRefreshTask) {
        NSLog("[BGRefresh] task started")

        // Re-schedule immediately so iOS knows we want recurring access.
        scheduleNext()

        fetchAndWrite { success in
            task.setTaskCompleted(success: success)
        }

        // iOS will kill the task after a short window - signal expiry cleanly.
        // fetchAndWrite's URLSession task will be cancelled by the system automatically.
        task.expirationHandler = {
            NSLog("[BGRefresh] task expired before completion")
            task.setTaskCompleted(success: false)
        }
    }
}
