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

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        let center = UNUserNotificationCenter.current()
        center.delegate = self

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
        completionHandler(.noData)
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
