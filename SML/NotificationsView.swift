//
//  NotificationsView.swift
//  SMC
//
//  Version: 1.0.0
//  Author: Nuvren.com
//
//  Назначение:
//  - Экран управления push уведомлениями
//  - Статус, включение, переход в системные настройки iOS
//

import SwiftUI
import UserNotifications
import UIKit

@MainActor
struct NotificationsView: View {

    @State private var permissionStatus: String = "Checking..."
    @State private var isWorking: Bool = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: statusIconName())
                        .foregroundStyle(statusColor())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Push notifications")
                            .font(.headline)
                        Text(permissionStatus)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Actions") {
                Button(isWorking ? "Working..." : "Enable notifications") {
                    Task { await requestNotifications() }
                }
                .disabled(isWorking || permissionStatus == "Enabled" || permissionStatus == "Provisional")

                Button("Open iPhone notification settings") {
                    openSystemSettings()
                }
            }

            Section {
                Text("Website email notifications continue to work even if push notifications are turned off.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshStatus() }
    }

    private func refreshStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized:
            permissionStatus = "Enabled"
        case .denied:
            permissionStatus = "Disabled"
        case .notDetermined:
            permissionStatus = "Not requested"
        case .provisional:
            permissionStatus = "Provisional"
        case .ephemeral:
            permissionStatus = "Ephemeral"
        @unknown default:
            permissionStatus = "Unknown"
        }
    }

    private func statusIconName() -> String {
        switch permissionStatus {
        case "Enabled", "Provisional":
            return "bell.badge.fill"
        case "Disabled":
            return "bell.slash"
        default:
            return "bell"
        }
    }

    private func statusColor() -> Color {
        switch permissionStatus {
        case "Enabled", "Provisional":
            return .green
        case "Disabled":
            return .red
        default:
            return .secondary
        }
    }

    private func requestNotifications() async {
        isWorking = true
        defer { isWorking = false }

        let center = UNUserNotificationCenter.current()

        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {}

        await refreshStatus()

        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized ||
            settings.authorizationStatus == .provisional ||
            settings.authorizationStatus == .ephemeral {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
