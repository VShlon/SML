//
//  AppDelegate.swift
//  SML
//
//  Version: 1.0.0
//  Author: Nuvren.com
//
//  Назначение:
//  - Делегат уведомлений
//  - Запрашивает разрешение на уведомления и регистрируется в APNs
//  - Получает token и сохраняет в PushState.shared
//  - Показывает уведомления баннером, когда приложение открыто
//  - По нажатию на push читает payload и открывает deeplink через PushState
//  - Обрабатывает запуск приложения из push
//

import UIKit
import UserNotifications
import BackgroundTasks

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    // One app-wide foreground event. WebView instances must not each start their
    // own network refresh when a user returns to the app.
    private var enteredBackgroundAt: Date?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Register background refresh task BEFORE app finishes launching (iOS requirement).
        SMLBackgroundRefresh.register()
        SMLBackgroundRefresh.scheduleNext()

        registerForPushIfNeeded(application: application)

        if let userInfo = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            DispatchQueue.main.async {
                PushState.shared.handleRemoteNotification(userInfo: userInfo)
            }
        }

        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        refreshPushRegistrationIfAuthorized(application: application)

        let absence = enteredBackgroundAt.map { Date().timeIntervalSince($0) } ?? 0
        enteredBackgroundAt = nil

        // This is the single source of truth for the widget and Live Activity
        // after foregrounding. It is intentionally asynchronous: the retained
        // WebView stays visible while the status is reconciled in the background.
        SMLBackgroundRefresh.refreshIfNeeded(minimumInterval: 2)
        NotificationCenter.default.post(
            name: .smlAppForegroundRefresh,
            object: nil,
            userInfo: ["absenceSeconds": absence]
        )
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        enteredBackgroundAt = Date()
        SMLBackgroundRefresh.scheduleNext()
    }

    private func registerForPushIfNeeded(application: UIApplication) {
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {

            case .notDetermined:
                center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                    if let error {
                        print("PUSH AUTH ERROR:", error.localizedDescription)
                        return
                    }

                    guard granted else {
                        print("PUSH AUTH: denied by user")
                        return
                    }

                    DispatchQueue.main.async {
                        application.registerForRemoteNotifications()
                    }
                }

            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }

            case .denied:
                print("PUSH AUTH: denied")

            @unknown default:
                break
            }
        }
    }

    private func refreshPushRegistrationIfAuthorized(application: UIApplication) {
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            default:
                break
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        DispatchQueue.main.async {
            PushState.shared.handleRemoteNotification(userInfo: userInfo)
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Silent push (content-available: 1) - refresh the widget for all staff.
        NSLog("[Push] silent push received - refreshing widget")
        SMLBackgroundRefresh.fetchAndWrite { success in
            completionHandler(success ? .newData : .noData)
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("APNS TOKEN:", token)

        DispatchQueue.main.async {
            PushState.shared.setApnsToken(token)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("APNS REGISTER FAILED:", error.localizedDescription)
    }
}
