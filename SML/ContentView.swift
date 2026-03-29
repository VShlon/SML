//  ContentView.swift
//  SMC
//
//  Version: 1.0.1
//  Author: Nuvren.com
//
//  Назначение:
//  - SwiftUI TabView
//  - UIKit bridge, чтобы ловить повторный тап по текущей вкладке
//  - При смене роли сбрасываем все вкладки, чтобы URL гарантированно обновлялись
//  - More открывается как sheet
//  - Меню строго привязано к роли
//

import SwiftUI
import UIKit

enum Tab: Hashable {
    case left1
    case left2
    case center
    case right1
    case right2
}

struct ContentView: View {

    @Environment(\.scenePhase) private var scenePhase

    @State private var selected: Tab = .left1
    @State private var lastNonMoreTab: Tab = .left1
    @State private var showMoreSheet: Bool = false

    @StateObject private var push = PushState.shared
    @StateObject private var roleState = RoleState.shared
    @State private var previousRoleMode: RoleState.Mode = RoleState.shared.mode

    @State private var left1Token = UUID()
    @State private var left2Token = UUID()
    @State private var centerToken = UUID()
    @State private var right1Token = UUID()

    @State private var left1Command: WebNavigationCommand? = nil
    @State private var left2Command: WebNavigationCommand? = nil
    @State private var centerCommand: WebNavigationCommand? = nil
    @State private var right1Command: WebNavigationCommand? = nil

    @State private var suppressReloadOnce: Bool = false
    @State private var needsHomeRefreshAfterExternal: Bool = false

    private let allowedHost = "stmaryslandscaping.ca"

    private let brand = UIColor(red: 67/255.0, green: 130/255.0, blue: 57/255.0, alpha: 1.0)
    private let blackSelected = UIColor(red: 67/255.0, green: 130/255.0, blue: 57/255.0, alpha: 1.0)
    private let blackUnselected = UIColor.black.withAlphaComponent(0.35)

    var body: some View {
        TabView(selection: $selected) {
            ForEach(makeTabs(for: roleState.mode), id: \.tab) { spec in
                tabBody(spec)
                    .tag(spec.tab)
                    .tabItem { tabLabel(spec) }
            }

            Color.clear
                .tag(Tab.right2)
                .tabItem {
                    Label { Text("") } icon: { Image(systemName: "ellipsis") }
                        .labelStyle(.iconOnly)
                }
        }
        .background(
            TabBarReselectDetector { didReselect in
                handleTabReselect(didReselect, mode: roleState.mode)
            }
            .frame(width: 0, height: 0)
        )
        .sheet(isPresented: $showMoreSheet) {
            SMCMoreRootView()
                .preferredColorScheme(.light)
        }
        .onAppear {
            applyTabBarAppearance()
            RoleState.shared.refresh()
        }
        .onChange(of: roleState.mode) { oldMode, newMode in
            applyTabBarAppearance()

            let fallback = tabForRoleTransition(from: oldMode, to: newMode, current: lastNonMoreTab)
            previousRoleMode = newMode

            suppressReloadOnce = true
            selected = fallback
            lastNonMoreTab = fallback
            resetAllTabsToRoot()
        }
        .onChange(of: selected) { _, newTab in
            if newTab == .right2 {
                showMoreSheet = true
                suppressReloadOnce = true
                selected = lastNonMoreTab
                return
            }

            lastNonMoreTab = newTab

            if suppressReloadOnce {
                suppressReloadOnce = false
                return
            }

            if shouldResetOnSelect(tab: newTab, mode: roleState.mode) {
                resetTabToRoot(newTab)
            }
        }
        .onReceive(push.$openCommand) { cmd in
            guard let cmd else { return }
            routeFromPush(cmd, mode: roleState.mode)
            push.consumeOpenCommand(cmd)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                applyTabBarAppearance()

                if needsHomeRefreshAfterExternal {
                    needsHomeRefreshAfterExternal = false
                    suppressReloadOnce = true
                    selected = .left1
                    lastNonMoreTab = .left1
                    resetAllTabsToRoot()
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private func shouldResetOnSelect(tab: Tab, mode: RoleState.Mode) -> Bool {
        return true
    }

    private func shouldResetOnReselect(tab: Tab, mode: RoleState.Mode) -> Bool {
        if tab == .right2 { return false }
        return true
    }

    private struct TabSpec {
        let tab: Tab
        let systemImage: String
        let isCenter: Bool
        let url: String
        let token: UUID
        let command: WebNavigationCommand?
    }

    private func makeTabs(for mode: RoleState.Mode) -> [TabSpec] {
        switch mode {
        case .guest:
            return [
                .init(tab: .left1, systemImage: "house", isCenter: false,
                      url: "https://stmaryslandscaping.ca/", token: left1Token, command: left1Command),
                .init(tab: .left2, systemImage: "leaf", isCenter: false,
                      url: "https://stmaryslandscaping.ca/services/", token: left2Token, command: left2Command),
                .init(tab: .center, systemImage: "phone", isCenter: true,
                      url: "https://stmaryslandscaping.ca/contact/", token: centerToken, command: centerCommand),
                .init(tab: .right1, systemImage: "square.grid.2x2", isCenter: false,
                      url: "https://stmaryslandscaping.ca/projects/", token: right1Token, command: right1Command),
            ]

        case .client:
            return [
                .init(tab: .left1, systemImage: "house", isCenter: false,
                      url: "https://stmaryslandscaping.ca/", token: left1Token, command: left1Command),
                .init(tab: .left2, systemImage: "doc.text", isCenter: false,
                      url: "https://stmaryslandscaping.ca/invoices/", token: left2Token, command: left2Command),
                .init(tab: .center, systemImage: "list.bullet.clipboard", isCenter: true,
                      url: "https://stmaryslandscaping.ca/my-requests/", token: centerToken, command: centerCommand),
                .init(tab: .right1, systemImage: "clock.arrow.circlepath", isCenter: false,
                      url: "https://stmaryslandscaping.ca/order-history/", token: right1Token, command: right1Command),
            ]

        case .worker:
            return [
                .init(tab: .left1, systemImage: "house", isCenter: false,
                      url: "https://stmaryslandscaping.ca/", token: left1Token, command: left1Command),
                .init(tab: .left2, systemImage: "calendar", isCenter: false,
                      url: "https://stmaryslandscaping.ca/account-workday/", token: left2Token, command: left2Command),
                .init(tab: .center, systemImage: "checklist", isCenter: true,
                      url: "https://stmaryslandscaping.ca/tasks-today/", token: centerToken, command: centerCommand),
                .init(tab: .right1, systemImage: "exclamationmark.bubble", isCenter: false,
                      url: "https://stmaryslandscaping.ca/report/", token: right1Token, command: right1Command),
            ]

        case .accountant:
            return [
                .init(tab: .left1, systemImage: "house", isCenter: false,
                      url: "https://stmaryslandscaping.ca/", token: left1Token, command: left1Command),
                .init(tab: .left2, systemImage: "calendar.badge.clock", isCenter: false,
                      url: "https://stmaryslandscaping.ca/monthly-billing/", token: left2Token, command: left2Command),
                .init(tab: .center, systemImage: "briefcase", isCenter: true,
                      url: "https://stmaryslandscaping.ca/account-workday/", token: centerToken, command: centerCommand),
                .init(tab: .right1, systemImage: "dollarsign.square", isCenter: false,
                      url: "https://stmaryslandscaping.ca/payroll-review/", token: right1Token, command: right1Command),
            ]

        case .admin:
            return [
                .init(tab: .left1, systemImage: "house", isCenter: false,
                      url: "https://stmaryslandscaping.ca/", token: left1Token, command: left1Command),
                .init(tab: .left2, systemImage: "plus.square", isCenter: false,
                      url: "https://stmaryslandscaping.ca/create-task/", token: left2Token, command: left2Command),
                .init(tab: .center, systemImage: "rectangle.3.group", isCenter: true,
                      url: "https://stmaryslandscaping.ca/workspace/", token: centerToken, command: centerCommand),
                .init(tab: .right1, systemImage: "tray.full", isCenter: false,
                      url: "https://stmaryslandscaping.ca/all-tasks/", token: right1Token, command: right1Command),
            ]
        }
    }

    @ViewBuilder
    private func tabBody(_ spec: TabSpec) -> some View {
        WebView(
            url: URL(string: spec.url)!,
            apnsToken: push.apnsToken,
            deviceId: push.deviceId,
            biometricEnabled: push.biometricEnabled,
            hasBiometricLogin: push.hasBiometricLogin,
            command: spec.command
        )
        .id(spec.token)
    }

    private func tabLabel(_ spec: TabSpec) -> some View {
        Label { Text("") } icon: {
            tabIcon(systemName: spec.systemImage, isCenter: spec.isCenter)
        }
        .labelStyle(.iconOnly)
    }

    private func tabIcon(systemName: String, isCenter: Bool) -> some View {
        if isCenter,
           let img = UIImage(systemName: systemImageFallback(systemName))?
            .withTintColor(brand, renderingMode: .alwaysOriginal) {
            return Image(uiImage: img)
        }
        return Image(systemName: systemImageFallback(systemName))
    }

    private func systemImageFallback(_ name: String) -> String { name }

    private func applyTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .white
        appearance.backgroundEffect = nil
        appearance.shadowColor = UIColor.black.withAlphaComponent(0.12)

        appearance.selectionIndicatorImage = UIImage()
        appearance.selectionIndicatorTintColor = .clear

        let item = UITabBarItemAppearance(style: .stacked)
        item.normal.titleTextAttributes = [.foregroundColor: UIColor.clear]
        item.selected.titleTextAttributes = [.foregroundColor: UIColor.clear]
        item.normal.iconColor = blackUnselected
        item.selected.iconColor = blackSelected

        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item

        let tabBarProxy = UITabBar.appearance()
        tabBarProxy.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBarProxy.scrollEdgeAppearance = appearance
        }
        tabBarProxy.isTranslucent = false
        tabBarProxy.backgroundColor = .white
    }

    private func handleTabReselect(_ tab: Tab, mode: RoleState.Mode) {
        if tab == .right2 {
            showMoreSheet = true
            return
        }

        if shouldResetOnReselect(tab: tab, mode: mode) {
            resetTabToRoot(tab)
        }
    }

    private func resetLeft1ToRoot() { left1Command = nil; left1Token = UUID() }
    private func resetLeft2ToRoot() { left2Command = nil; left2Token = UUID() }
    private func resetCenterToRoot() { centerCommand = nil; centerToken = UUID() }
    private func resetRight1ToRoot() { right1Command = nil; right1Token = UUID() }

    private func resetAllTabsToRoot() {
        resetLeft1ToRoot()
        resetLeft2ToRoot()
        resetCenterToRoot()
        resetRight1ToRoot()
    }

    private func resetTabToRoot(_ tab: Tab) {
        switch tab {
        case .left1: resetLeft1ToRoot()
        case .left2: resetLeft2ToRoot()
        case .center: resetCenterToRoot()
        case .right1: resetRight1ToRoot()
        case .right2: break
        }
    }

    private func isExternalURL(_ url: URL) -> Bool {
        let scheme = (url.scheme ?? "").lowercased()
        if scheme != "http" && scheme != "https" { return false }

        let host = (url.host ?? "").lowercased()
        if host.isEmpty { return false }

        if host == allowedHost || host.hasSuffix("." + allowedHost) { return false }
        return true
    }

    private func openExternally(_ url: URL) {
        DispatchQueue.main.async { UIApplication.shared.open(url, options: [:]) }
    }

    private func tabForRoleTransition(from oldMode: RoleState.Mode, to newMode: RoleState.Mode, current: Tab) -> Tab {
        if newMode == .guest {
            return .left1
        }
        switch current {
        case .left1: return .left1
        case .left2: return .left2
        case .center: return .center
        case .right1: return .right1
        case .right2: return .left1
        }
    }

    private func routeFromPush(_ cmd: PushState.PushOpenCommand, mode: RoleState.Mode) {
        guard let url = cmd.url else { return }

        left1Command = nil
        left2Command = nil
        centerCommand = nil
        right1Command = nil

        if showMoreSheet { showMoreSheet = false }

        if isExternalURL(url) {
            needsHomeRefreshAfterExternal = true
            suppressReloadOnce = true
            selected = .left1
            lastNonMoreTab = .left1
            openExternally(url)
            return
        }

        let path = url.path.lowercased()
        var target: Tab = .left1

        switch mode {
        case .guest:
            if path.contains("/services") { target = .left2 }
            else if path.contains("/contact") { target = .center }
            else if path.contains("/projects") { target = .right1 }
            else { target = .left1 }

        case .client:
            if path.contains("/invoices") { target = .left2 }
            else if path.contains("/my-requests") { target = .center }
            else if path.contains("/order-history") { target = .right1 }
            else { target = .left1 }

        case .worker:
            if path.contains("/account-workday") { target = .left2 }
            else if path.contains("/tasks-today") { target = .center }
            else if path.contains("/report") { target = .right1 }
            else { target = .left1 }

        case .accountant:
            if path.contains("/monthly-billing") { target = .left2 }
            else if path.contains("/account-workday") { target = .center }
            else if path.contains("/payroll-review") { target = .right1 }
            else { target = .left1 }

        case .admin:
            if path.contains("/create-task") { target = .left2 }
            else if path.contains("/workspace") { target = .center }
            else if path.contains("/all-tasks") { target = .right1 }
            else { target = .left1 }
        }

        suppressReloadOnce = true
        selected = target
        lastNonMoreTab = target

        let nav = WebNavigationCommand(id: cmd.id, url: url)

        switch target {
        case .left1: left1Command = nav
        case .left2: left2Command = nav
        case .center: centerCommand = nav
        case .right1: right1Command = nav
        case .right2: break
        }
    }
}

private struct TabBarReselectDetector: UIViewControllerRepresentable {

    let onReselect: (Tab) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        context.coordinator.attach(to: vc)
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.attach(to: uiViewController)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onReselect: onReselect)
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {

        private let onReselect: (Tab) -> Void
        private weak var tabBarController: UITabBarController?
        private var lastIndex: Int?

        init(onReselect: @escaping (Tab) -> Void) {
            self.onReselect = onReselect
        }

        func attach(to vc: UIViewController) {
            guard tabBarController == nil else { return }

            DispatchQueue.main.async { [weak self, weak vc] in
                guard let self, let vc else { return }

                var p: UIViewController? = vc
                while let parent = p?.parent {
                    if let tbc = parent as? UITabBarController {
                        self.tabBarController = tbc
                        tbc.delegate = self
                        self.lastIndex = tbc.selectedIndex
                        return
                    }
                    p = parent
                }
            }
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            let idx = tabBarController.selectedIndex

            if let last = lastIndex, last == idx {
                onReselect(mapIndexToTab(idx))
            }

            lastIndex = idx
        }

        private func mapIndexToTab(_ idx: Int) -> Tab {
            switch idx {
            case 0: return .left1
            case 1: return .left2
            case 2: return .center
            case 3: return .right1
            default: return .right2
            }
        }
    }
}
