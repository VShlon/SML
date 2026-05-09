//
//  SMLApp.swift
//  SML
//
//  Version: 1.0.1
//  Author: Nuvren.com
//
//  iPhone: TabView (ContentView)
//  iPad:   NavigationSplitView sidebar (iPadRootView)
//

import SwiftUI

@main
struct SMLApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootDispatcher()
        }
    }
}

// Switches between iPad sidebar layout and iPhone tab bar layout.
private struct RootDispatcher: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            iPadRootView()
        } else {
            ContentView()
        }
    }
}
