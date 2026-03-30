//
//  SMLApp.swift
//  SML
//
//  Version: 1.0.0
//  Author: Nuvren.com
//
//  Назначение:
//  - Главная точка входа приложения
//  - Подключает AppDelegate
//  - Запускает ContentView
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
