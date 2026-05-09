//
//  SMLLiveActivityManager.swift
//  SML
//
//  Manages starting, updating and ending Live Activities.
//  Called from WebView.swift when JS posts smlLiveActivity messages.
//
//  ⚠️ TARGET MEMBERSHIP: этот файл должен быть только в таргете SML.
//     SMLWidget extension не использует LiveActivity напрямую.
//

import ActivityKit
import Foundation

@available(iOS 16.2, *)
final class SMLLiveActivityManager {

    static let shared = SMLLiveActivityManager()
    private init() {}

    // MARK: - Token update callback
    // Parameters: (type, hexToken, orderId, isSandbox)
    // type is "workday" or "order"
    var onTokenUpdate: ((String, String, String, Bool) -> Void)?

    // MARK: - Active activities

    private var workdayActivity: Activity<WorkdayActivityAttributes>?
    private var orderActivity:   Activity<OrderActivityAttributes>?

    // MARK: - Token observation (one Task per activity instance, never accumulate)

    private var workdayTokenTask: Task<Void, Never>?
    private var orderTokenTask:   Task<Void, Never>?
    private var observedWorkdayActivityId: String?
    private var observedOrderActivityId:   String?

    // MARK: - Workday (workers)

    func startWorkday(workerName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endWorkday()
        let state = WorkdayActivityAttributes.ContentState(
            status: "active",
            adjustedStart: Date(),
            workerName: workerName
        )
        do {
            workdayActivity = try Activity.request(
                attributes: WorkdayActivityAttributes(),
                content: .init(state: state, staleDate: nil),
                pushType: .token
            )
            observeWorkdayToken()
        } catch {
            NSLog("[LiveActivity] startWorkday failed: \(error)")
        }
    }

    // Observes the first push token for the workday activity and reports it via onTokenUpdate.
    // Guard prevents duplicate Tasks when syncWorkday is called repeatedly for the same activity.
    private func observeWorkdayToken() {
        guard let activity = workdayActivity else { return }
        guard activity.id != observedWorkdayActivityId else { return }
        observedWorkdayActivityId = activity.id
        workdayTokenTask?.cancel()
        let isSandbox = UserDefaults(suiteName: "group.ca.stmaryslandscaping.app")?.bool(forKey: "sml_is_sandbox_push") ?? false
        workdayTokenTask = Task { [weak self] in
            for await tokenData in activity.pushTokenUpdates {
                guard !Task.isCancelled else { break }
                let hex = tokenData.map { String(format: "%02x", $0) }.joined()
                NSLog("[LiveActivity] workday push token: \(hex)")
                self?.onTokenUpdate?("workday", hex, "", isSandbox)
                break
            }
        }
    }

    // Syncs workday activity with server state (called on page load).
    // Reattaches to a running activity after app restart, or starts a new one.
    // pauseStartUnix: unix timestamp of when current pause started (0 if not paused or unknown).
    func syncWorkday(workerName: String, adjustedStartUnix: Double, status: String, pauseStartUnix: Double = 0, isRetry: Bool = false) {
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        NSLog("[LiveActivity] syncWorkday called: name=\(workerName) start=\(adjustedStartUnix) status=\(status) enabled=\(enabled)")
        guard enabled else { return }

        // Workday is over - end any running activity and bail.
        if status != "open" && status != "active" && status != "paused" {
            endWorkday()
            return
        }

        let adjustedStart = adjustedStartUnix > 0
            ? Date(timeIntervalSince1970: adjustedStartUnix)
            : Date()
        let liveStatus = status == "paused" ? "paused" : "active"

        // When paused: use server-provided pause start or fall back to now.
        let pauseStart: Date = (liveStatus == "paused")
            ? (pauseStartUnix > 0 ? Date(timeIntervalSince1970: pauseStartUnix) : Date())
            : Date(timeIntervalSince1970: 0)

        if let existing = Activity<WorkdayActivityAttributes>.activities.first {
            NSLog("[LiveActivity] syncWorkday: updating existing activity id=\(existing.id)")
            workdayActivity = existing
            let newState = WorkdayActivityAttributes.ContentState(
                status: liveStatus,
                adjustedStart: adjustedStart,
                workerName: workerName,
                pauseStart: pauseStart
            )
            Task { await existing.update(.init(state: newState, staleDate: nil)) }
            observeWorkdayToken()
        } else {
            NSLog("[LiveActivity] syncWorkday: starting NEW activity")
            let state = WorkdayActivityAttributes.ContentState(
                status: liveStatus,
                adjustedStart: adjustedStart,
                workerName: workerName,
                pauseStart: pauseStart
            )
            do {
                workdayActivity = try Activity.request(
                    attributes: WorkdayActivityAttributes(),
                    content: .init(state: state, staleDate: nil),
                    pushType: .token
                )
                NSLog("[LiveActivity] syncWorkday: started id=\(workdayActivity?.id ?? "nil")")
                observeWorkdayToken()
            } catch {
                NSLog("[LiveActivity] syncWorkday start failed: \(error)")
                // "visibility" means the app wasn't fully in the foreground yet.
                // Retry once after a short delay - by then the UI is visible.
                let desc = "\(error)".lowercased()
                if !isRetry && (desc.contains("visibility") || desc.contains("foreground")) {
                    let name   = workerName
                    let start  = adjustedStartUnix
                    let st     = status
                    let pause  = pauseStartUnix
                    Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        guard let self else { return }
                        await MainActor.run { [self] in
                            self.syncWorkday(
                                workerName: name,
                                adjustedStartUnix: start,
                                status: st,
                                pauseStartUnix: pause,
                                isRetry: true
                            )
                        }
                    }
                }
            }
        }
    }

    func pauseWorkday() {
        guard let activity = workdayActivity else { return }
        Task {
            var state = activity.content.state
            state.status = "paused"
            // pauseStart = now, so the break timer counts up from this moment.
            state.pauseStart = Date()
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func resumeWorkday(totalPausedSeconds: Int) {
        guard let activity = workdayActivity else { return }
        Task {
            var state = activity.content.state
            state.status = "active"
            // Push adjustedStart forward by paused duration so the working timer is correct.
            state.adjustedStart = state.adjustedStart.addingTimeInterval(Double(totalPausedSeconds))
            // Reset pauseStart - it is not shown when status is active.
            state.pauseStart = Date(timeIntervalSince1970: 0)
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func endWorkday() {
        // Cancel token observation before clearing the reference.
        workdayTokenTask?.cancel()
        workdayTokenTask = nil
        observedWorkdayActivityId = nil
        // Capture all running activities before clearing the reference.
        let allActivities = Activity<WorkdayActivityAttributes>.activities
        let primary = workdayActivity ?? allActivities.first
        workdayActivity = nil
        guard primary != nil || !allActivities.isEmpty else { return }
        Task {
            // Show "Day Ended" on the primary activity for 1 hour.
            if let activity = primary {
                var state = activity.content.state
                state.status = "ended"
                await activity.end(
                    .init(state: state, staleDate: nil),
                    dismissalPolicy: .after(Date().addingTimeInterval(3600))
                )
            }
            // Dismiss any orphaned activities immediately.
            for orphan in allActivities where orphan.id != primary?.id {
                await orphan.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - Order status (clients)

    func startOrder(orderId: String, serviceName: String, status: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endOrder(orderId: orderId)
        let attrs = OrderActivityAttributes(orderId: orderId)
        let state = OrderActivityAttributes.ContentState(
            status: status,
            serviceName: serviceName,
            updatedAt: Date()
        )
        do {
            orderActivity = try Activity.request(
                attributes: attrs,
                content: .init(state: state, staleDate: nil),
                pushType: .token
            )
            observeOrderToken(orderId: orderId)
        } catch {
            NSLog("[LiveActivity] startOrder failed: \(error)")
        }
    }

    // Observes the first push token for the order activity and reports it via onTokenUpdate.
    // Guard prevents duplicate Tasks when syncOrder is called repeatedly for the same activity.
    private func observeOrderToken(orderId: String) {
        guard let activity = orderActivity else { return }
        guard activity.id != observedOrderActivityId else { return }
        observedOrderActivityId = activity.id
        orderTokenTask?.cancel()
        let isSandbox = UserDefaults(suiteName: "group.ca.stmaryslandscaping.app")?.bool(forKey: "sml_is_sandbox_push") ?? false
        orderTokenTask = Task { [weak self] in
            for await tokenData in activity.pushTokenUpdates {
                guard !Task.isCancelled else { break }
                let hex = tokenData.map { String(format: "%02x", $0) }.joined()
                NSLog("[LiveActivity] order push token orderId=\(orderId): \(hex)")
                self?.onTokenUpdate?("order", hex, orderId, isSandbox)
                break
            }
        }
    }

    // Syncs order activity with server state (called on page load).
    // Reattaches after app restart, or starts a new one if needed.
    func syncOrder(orderId: String, serviceName: String, status: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if status == "completed" || status == "cancelled" {
            endOrder(orderId: orderId)
            return
        }
        let existing = Activity<OrderActivityAttributes>.activities.first(where: {
            $0.attributes.orderId == orderId
        }) ?? Activity<OrderActivityAttributes>.activities.first
        if let existing = existing {
            orderActivity = existing
            let resolvedName = serviceName.isEmpty ? existing.content.state.serviceName : serviceName
            let newState = OrderActivityAttributes.ContentState(
                status: status,
                serviceName: resolvedName,
                updatedAt: Date()
            )
            Task { await existing.update(.init(state: newState, staleDate: nil)) }
            observeOrderToken(orderId: orderId)
        } else {
            startOrder(orderId: orderId, serviceName: serviceName, status: status)
        }
    }

    func updateOrder(status: String) {
        guard let activity = orderActivity else { return }
        if status == "completed" {
            // Clear synchronously to prevent race with endOrder.
            orderTokenTask?.cancel()
            orderTokenTask = nil
            observedOrderActivityId = nil
            orderActivity = nil
        }
        Task {
            let state = OrderActivityAttributes.ContentState(
                status: status,
                serviceName: activity.content.state.serviceName,
                updatedAt: Date()
            )
            await activity.update(.init(state: state, staleDate: nil))
            if status == "completed" {
                await activity.end(
                    .init(state: state, staleDate: nil),
                    dismissalPolicy: .after(Date().addingTimeInterval(7200))
                )
            }
        }
    }

    func endOrder(orderId: String) {
        // If orderId is empty, end whatever activity is running.
        let match = orderId.isEmpty
            ? orderActivity
            : (orderActivity?.attributes.orderId == orderId ? orderActivity : nil)
        guard let activity = match else { return }
        // Cancel token observation before ending the activity.
        orderTokenTask?.cancel()
        orderTokenTask = nil
        observedOrderActivityId = nil
        orderActivity = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
