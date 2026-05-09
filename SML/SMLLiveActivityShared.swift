//
//  SMLLiveActivityShared.swift
//  SML + SMLWidget
//
//  ActivityAttributes shared between the main app and widget extension.
//  Must be compiled in BOTH targets.
//

import ActivityKit
import Foundation

// MARK: - Workday Activity (workers)
// Shows elapsed workday time on lock screen and Dynamic Island.

struct WorkdayActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// "active" | "paused" | "ended"
        var status: String
        /// Adjusted start date: original start + total paused seconds.
        /// Text(adjustedStart, style: .timer) counts actual working time.
        var adjustedStart: Date
        /// Human-readable worker name shown on lock screen.
        var workerName: String
        /// When the current pause started. Only meaningful when status == "paused".
        /// Used to show break duration as a separate timer that resets on each pause.
        var pauseStart: Date

        init(status: String, adjustedStart: Date, workerName: String, pauseStart: Date = Date(timeIntervalSince1970: 0)) {
            self.status = status
            self.adjustedStart = adjustedStart
            self.workerName = workerName
            self.pauseStart = pauseStart
        }

        // Custom decode so existing activities without pauseStart don't crash.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            status       = try c.decode(String.self, forKey: .status)
            adjustedStart = try c.decode(Date.self,   forKey: .adjustedStart)
            workerName   = try c.decode(String.self, forKey: .workerName)
            pauseStart   = try c.decodeIfPresent(Date.self, forKey: .pauseStart) ?? Date(timeIntervalSince1970: 0)
        }

        private enum CodingKeys: String, CodingKey {
            case status, adjustedStart, workerName, pauseStart
        }
    }
}

// MARK: - Order Activity (clients)
// Shows current service request progress on lock screen and Dynamic Island.

struct OrderActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// "submitted" | "scheduled" | "in_progress" | "completed"
        var status: String
        /// Display name of the service, e.g. "Lawn & Bed Maintenance"
        var serviceName: String
        /// When status last changed
        var updatedAt: Date
    }
    /// Unique order identifier, used as Live Activity ID
    var orderId: String
}
