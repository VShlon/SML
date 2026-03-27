//
//  SMLApp.swift
//  sml
//
//  Версия: 1.0.0
//  Автор: Nuvren.com
//
//  Назначение (по-русски):
//  - Главная точка входа приложения;
//  - Подключает AppDelegate (нужен для локальных уведомлений в foreground);
//  - Запускает ContentView (вкладки сайта + вкладка App-настроек).
//

import SwiftUI

@main
struct SMLApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
