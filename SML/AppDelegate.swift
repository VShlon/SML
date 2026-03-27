//
//  AppDelegate.swift
//  sml
//
//  Version: 1.0.0
//  Author: Nuvren.com
//
//  Назначение:
//  - Делегат уведомлений
//  - ✅ Запрашивает разрешение на уведомления (первый запуск) и регистрируется в APNs
//  - Получает token и сохраняет в PushState.shared
//  - Показывает уведомления баннером даже когда приложение открыто
//  - ✅ По нажатию на push читает payload и открывает deeplink через PushState
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

        // ✅ 1) Запрос разрешения (если ещё не спрашивали) + регистрация в APNs
        refreshPushRegistration(application: application, center: center)

        // ✅ 2) Если приложение запущено тапом по push — обработаем deeplink сразу
        if let userInfo = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            handleRemoteNotification(userInfo: userInfo)
        }

        return true
    }


    private func refreshPushRegistration(application: UIApplication, center: UNUserNotificationCenter = .current()) {
        center.getNotificationSettings { settings in
            let st = settings.authorizationStatus

            switch st {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, err in
                    if let err = err {
                        print("PUSH AUTH ERROR:", err.localizedDescription)
                        return
                    }
                    if granted {
                        DispatchQueue.main.async {
                            application.registerForRemoteNotifications()
                        }
                    } else {
                        print("PUSH AUTH: denied by user")
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

    func applicationDidBecomeActive(_ application: UIApplication) {
        refreshPushRegistration(application: application)
    }
    // Баннеры когда приложение активно
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }

    // ✅ Пользователь нажал на push
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        handleRemoteNotification(userInfo: userInfo)
    }

    private func handleRemoteNotification(userInfo: [AnyHashable: Any]) {
        DispatchQueue.main.async {
            PushState.shared.handleRemoteNotification(userInfo: userInfo)
        }
    }


    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        handleRemoteNotification(userInfo: userInfo)
        completionHandler(.newData)
    }

    // APNs token получен
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

    // APNs регистрация провалилась
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("APNS REGISTER FAILED:", error.localizedDescription)
    }
}
