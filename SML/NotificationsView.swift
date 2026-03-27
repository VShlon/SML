//
//  NotificationsView.swift
//  sml
//
//  Version: 1.0.0
//  Author: Nuvren.com
//
//  Назначение:
//  - Экран управления push уведомлениями для клиента
//  - Статус, включение, переход в системные настройки iOS
//


import SwiftUI
import UserNotifications
import UIKit

@MainActor
struct NotificationsView: View {

    @State private var permissionStatus: String = "Checking..."
    @State private var isWorking = false

    private let brandColor = AppConfig.brandColorSwiftUI

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: statusIconName())
                        .foregroundStyle(statusColor())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Push Notifications")
                            .font(.headline)
                            .foregroundStyle(brandColor)
                        Text(permissionStatus)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Actions") {
                Button(isWorking ? "Working..." : "Enable Notifications") {
                    Task { await requestNotifications() }
                }
                .disabled(isWorking || permissionStatus == "Enabled" || permissionStatus == "Provisional")

                Button("Open iPhone Notification Settings") {
                    openSystemSettings()
                }
            }

            Section {
                Text("Email notifications from the website continue to work even if push notifications are turned off.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(brandColor)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshStatus() }
    }

    private func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()

        switch settings.authorizationStatus {
        case .authorized:
            permissionStatus = "Enabled"
        case .denied:
            permissionStatus = "Disabled"
        case .notDetermined:
            permissionStatus = "Not Requested"
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
        if permissionStatus == "Disabled" {
            return .red
        }
        return brandColor
    }

    private func requestNotifications() async {
        isWorking = true
        defer { isWorking = false }

        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {}

        await refreshStatus()

        let settings = await UNUserNotificationCenter.current().notificationSettings()
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
